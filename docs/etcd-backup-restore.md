# BCM etcd バックアップ・リストア試験

作成日: 2026-09-25（JST）

## 目的と合格条件

BCM が管理する Kubernetes の etcd スナップショットを取得し、承認済みの復旧手順でリストアした後、Kubernetes API リソースがバックアップ時点へ戻ったことを簡易に確認する。

合格には次のすべてを満たす必要がある。

1. BCM の etcd status が正常で、Kubernetes API の `/readyz` が成功する。
2. 全 Kubernetes Node が `Ready` へ戻る。
3. バックアップ前に作成した namespace、ConfigMap、ServiceAccount、Service、Deployment が存在する。
4. バックアップ後に変更した ConfigMap の値が `before-backup` へ戻る。
5. バックアップ後に削除した ServiceAccount、Service、Deployment が復元される。
6. バックアップ後に新規作成した ConfigMap `after-backup` が存在しない。

この確認は **Kubernetes API オブジェクトが etcd の時点へ戻ったこと**を対象とする。PV / PVC のメタデータは etcd に含まれるが、TopoLVM の LV、ファイルシステム内のデータ、外部データベース、コンテナレジストリ等の実データは etcd スナップショットだけでは復元されない。ワークロードデータの復旧試験は別に行う。

## 復元操作の安全条件

etcd リストアはクラスタ全体を過去へ戻す破壊的操作である。実運用クラスタでは行わず、廃棄可能な検証環境、承認済みの停止時間、VM または基盤側の追加復旧手段を用意する。

[Kubernetes の公式手順](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#restoring-an-etcd-cluster) は、API server を稼働させたまま etcd をリストアしないこと、全 API server の停止、全 etcd instance の復元、API server の再開を求めている。scheduler、controller-manager、kubelet も stale data を避けるため再起動を推奨している。

本ヘッドにある BCM 11 の `cm-etcd-manage` を読み取り確認したところ、`restore <dst_node> <src_file>` は次を前提にする。

- 復元先ノードが etcd member / learner の configuration overlay に含まれない。
- 復元先の etcd service が停止している。
- 復元先の etcd spool directory が空である。
- snapshot が BCM ヘッドと復元先ノードの同一パスから読める。
- 復元時は指定した 1 ノードを新しい logical cluster として初期化し、そのノードを member overlay へ追加する。

そのため、**稼働中の 3 member etcd に `restore` だけを実行する手順にはしない**。既存 member の停止・overlay からの除外、API server の停止、最初の 1 member の復元、残り member の再参加、Kubernetes component の再開順は、対象 BCM / `cmdaemon` / `cm-etcd-manage` の版に一致する NVIDIA の復旧手順またはサポート回答で確定する。公開資料からは BCM 11 の multi-member cluster を対象にした完全なリストア順を確認できていないため、本書では推測で補完しない。

## 前提情報を記録する

実行場所は BCM ヘッドノードの root shell。`<KUBE_CLUSTER>`、`<SNAPSHOT_DIR>`、`<SNAPSHOT_FILE>`、`<RESTORE_NODE>` は対象環境の確認済み値に置き換える。秘密情報や実接続情報を Git 管理文書へ転記しない。

```bash
date --iso-8601=seconds
cmsh -c 'main versioninfo'
dpkg-query -W -f='${Package}\t${Version}\n' cmdaemon cm-setup 2>/dev/null \
  || rpm -q cmdaemon cm-setup
/cm/local/apps/cmd/scripts/cm-etcd-manage --help
/cm/local/apps/cmd/scripts/cm-etcd-manage \
  --kube-cluster <KUBE_CLUSTER> status
kubectl version
kubectl get --raw='/readyz?verbose'
kubectl get nodes -o wide
```

上記の出力と以降の証跡は `input/80-etcd-restore/<実施日時>/` 等の Git 管理外ディレクトリへ保存する。etcd snapshot には Kubernetes Secret を含むクラスタ状態全体が入るため、アクセス制限・暗号化・保持期限を設定し、Git へ追加しない。

## 1. バックアップ前の検証リソースを作る

このリポジトリの [`examples/etcd-restore-check.yaml`](examples/etcd-restore-check.yaml) は Deployment の replica を 0 としており、Pod 起動や image pull を発生させない。既存の同名 namespace がある場合は上書き・削除せず、試験を停止して前回の記録を確認する。

```bash
kubectl get namespace etcd-restore-check
# NotFound であることを確認してから実行する
kubectl apply -f docs/examples/etcd-restore-check.yaml
kubectl get namespace etcd-restore-check -o json
kubectl -n etcd-restore-check get configmap,serviceaccount,service,deployment \
  -l app.kubernetes.io/name=etcd-restore-check -o json
```

期待結果は namespace と 4 種類の namespaced resource が作成され、ConfigMap の `data.checkpoint` と Deployment の `spec.replicas` がそれぞれ `before-backup` と `0` であること。出力はバックアップとは別の場所にも保存し、Service の `clusterIP`、各 resource の `uid` と作成日時を後で比較できるようにする。

## 2. etcd snapshot を取得・検証する

NVIDIA の [DGX Kubernetes Updates](https://docs.nvidia.com/dgx-superpod/update-guide/latest/kubernetes-updates.html) は、BCM 10 以降の例として leader から `/cm/shared/etcd-backups` へバックアップするコマンドを掲載している。本環境では配置先が `PATH` にないため絶対パスを使用する。

```bash
# <SNAPSHOT_DIR> は BCM ヘッドと etcd member の双方から同じパスで参照でき、
# root 以外から読み取れない保存先を事前に用意する
/cm/local/apps/cmd/scripts/cm-etcd-manage \
  --kube-cluster <KUBE_CLUSTER> backup <SNAPSHOT_DIR>
```

コマンドの終了コード 0、出力された snapshot file の非ゼロ容量を確認する。etcd v3.5 以降では `etcdutl snapshot status` が推奨されるため、対象ノードに `etcdutl` がある場合は hash、revision、total keys、total size も記録する。`etcdutl` がない場合に限り、対象版で利用できる `etcdctl snapshot status` を使用し、deprecated 表示も記録する。

```bash
sha256sum <SNAPSHOT_FILE>
/cm/local/apps/etcd/current/bin/etcdutl \
  --write-out=table snapshot status <SNAPSHOT_FILE>
```

`cm-etcd-manage` のバックアップ成功表示だけでリストア可能と判定せず、snapshot status と別媒体への保全を確認する。

## 3. バックアップ後の差分を作る

次の変更により、復元判定の正負両方を用意する。これらはバックアップ成功と snapshot 保全を確認した後に実行する。

```bash
kubectl -n etcd-restore-check patch configmap before-backup \
  --type=merge -p '{"data":{"checkpoint":"after-backup"}}'
kubectl -n etcd-restore-check delete \
  serviceaccount/before-backup service/before-backup deployment.apps/before-backup
kubectl -n etcd-restore-check create configmap after-backup \
  --from-literal=checkpoint=after-backup

kubectl -n etcd-restore-check get configmap,serviceaccount,service,deployment -o wide
```

この時点では `before-backup` ConfigMap の値が `after-backup`、3 resource が削除済み、`after-backup` ConfigMap が存在することを確認する。ここで取得した出力も Git 管理外の証跡へ保存する。

## 4. 承認済みの BCM 復旧手順を実行する

前述の安全条件を満たし、対象版の multi-member 復旧順を確定してから、別途承認された手順を実行する。現在の `cm-etcd-manage` が表示するリストア構文は次のとおりだが、これは単独で完結する 3 member cluster の復旧手順ではない。

```text
/cm/local/apps/cmd/scripts/cm-etcd-manage \
  --kube-cluster <KUBE_CLUSTER> restore <RESTORE_NODE> <SNAPSHOT_FILE>
```

実施時は、API server / etcd / Kubernetes component の停止・開始、member overlay の変更、各 member の再参加、失敗と再試行を実行順に記録する。途中で前提が一致しない、snapshot が読めない、spool が空でない、旧 member が動作している等の場合は続行しない。

### 復元後の `update_configmap` / `update_apiserver` の意味

2026-09-25 の追加調査。ユーザーから、別案件で `cm-kubeadm-manager` の両操作と、`update_apiserver` に headnode を指定する手順が使われていたとの情報を受けた。手順原本・版・実行日時・出力は未共有。本ヘッドと [NVIDIA の公開案内](https://docs.nvidia.com/dgx-superpod/update-guide/latest/kubernetes-updates.html) で確認できた名前は **`cm-kubeadm-manage`（末尾の r なし）** だった。別案件の名前が誤記、alias、独自 wrapper のいずれかは未確認であり、以下は本ヘッドにある BCM 11 版の動作を説明する。

etcd snapshot の復元により Kubernetes 内の `kube-system/kubeadm-config` もバックアップ時点へ戻る。一方、BCM の管理設定と各ノード上の設定ファイルは、etcd snapshot の復元では巻き戻らない。復旧時に etcd の構成・接続先を変えた場合、これらを復旧後の実構成に合わせる目的で両操作を使うと考えられる。

| 操作 | 今回の版で確認できた更新内容 | 引数・依存関係 |
|---|---|---|
| `update_configmap` | BCM の対象 etcd cluster の member 割当から接続先を求め、`kube-system/kubeadm-config` の `data.ClusterConfiguration` 内の `etcd.external.endpoints` を更新する。BCM の Kubelet role のオプションも扱い、各 control-plane ノードへ `/root/.kube/kubeadm-init-<KUBE_CLUSTER>.yaml` を書き出す | ノード引数なし。BCM が実効 Kubelet role の `controlPlane` を有効と認識する対象ノードへ配布する。Kubernetes API への接続と対象ノードへの SSH が必要 |
| `update_apiserver <NODE>` | 指定ノードの API server–etcd 間のクライアント証明書・鍵を再生成する処理を呼び、必要に応じて etcd CA 証明書を補う。ノード上の kubeadm-init YAML から `kube-apiserver.yaml` を再生成し、`crictl` で既存 API server Pod を停止・削除して kubelet に再作成させる | ノード引数は更新先の SSH 接続先。ConfigMap を自ら取得・更新する処理はなく、更新済みのローカル YAML が必要 |

`update_configmap` の接続先の根拠は **BCM の overlay の割当**であり、etcd の実メンバーを照会して自動修正する処理ではない。learner 用として扱われる overlay は除外する。実メンバーと BCM の割当が一致していることが前提となる。任意のアプリケーション用 ConfigMap を復元するコマンドでもない。

`update_apiserver` 内の証明書処理は、この版では既存の etcd CA 証明書を無条件には上書きしない。また、API server がクライアントへ提示するサーバー証明書を更新する `update_apiserver_cert` は別操作である。証明書に関係するという理由だけで、これらを同じ操作とは扱わない。

API が利用でき、BCM の member 割当を確定済みなら、設定更新の依存順は `update_configmap` → `update_apiserver <各CP>` となる。ConfigMap の変更だけでは稼働中の API server の `--etcd-servers` に自動反映されないことは、[Kubernetes の再設定手順](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/#reflecting-clusterconfiguration-changes-on-control-plane-nodes) とも整合する。

ただし、全 API server が停止中または復旧先 etcd へ接続できない場合、`update_configmap` は ConfigMap の読み取りから失敗する。その場合の最初の API server の復旧方法は、既存 YAML の正しさと対象版の復旧手順に依存する。先に `update_apiserver` を実行する手順にもこのような前提があり得るため、手順全体を確認せず順番だけを入れ替えない。同じ接続先・設定へ戻す復元なら、snapshot を戻したという事実だけで両操作が毎回必須になるわけではない。

両操作は更新・再起動を伴う復旧後の設定整合であり、[復元結果の簡易確認](#5-復元結果を簡易確認する) とは別の作業である。今回の調査では実行していない。

### etcd クライアント証明書が見つからない場合の復旧

2026-09-25 のユーザー報告: `crictl` で kube-apiserver のログを確認し、`/etc/kubernetes/pki/<KUBE_CLUSTER>/apiserver-etcd-client.crt: no such file or directory` を確認した。クラスタ識別子は公開可否未確認のため匿名化した。ユーザーの正確な実行コマンド・時刻、原ログ、対象ノード・BCM 版は未共有。コンテナから証明書が見えないことが起動阻害要因と考えられるが、ホスト上の欠落・mount 不整合・誤った参照パスは未切り分け。

追加のユーザー回答で、障害環境は **BCM 11.33、CP 3 台中 1 台は稼働し kubectl が利用可能**と判明した（ユーザー報告、原出力未共有）。正常 CP は維持し、障害 CP を 1 台ずつ扱う。正常経路で ConfigMap を照会できるため、下記 3 の API 利用可能時の分岐を使える。ただしツールはヘッドの `/root/.kube/config-<KUBE_CLUSTER>` を使用するため、その kubeconfig からも API に接続できることを先に確認する。

以下は **未実行の条件付き復旧手順**。確認した実装は本ヘッドの `cmdaemon 11.0-165270-cm11.0-14a0291f4f` にある `cm-kubeadm-manage`。障害環境の同名コマンドが同じ動作とは未確認のため、ヘルプと版を照合する。実行場所は BCM ヘッドの root shell、ノード内操作は対象 CP の root shell。CMDaemon の対象クラスタ・CA 情報が正しく、ヘッドから CP への SSH と証明書発行処理が利用できることが前提。各手順の成功を確認して次へ進み、複数 CP を一括処理しない。

#### 1. ツールと etcd の確認（BCM ヘッド）

```bash
KUBE_CLUSTER='<KUBE_CLUSTER>'
CP_NODE='<AFFECTED_CONTROL_PLANE>'
cmsh -c 'main versioninfo'
/cm/local/apps/cmd/scripts/cm-kubeadm-manage --help
/cm/local/apps/cmd/scripts/cm-etcd-manage --help
/cm/local/apps/cmd/scripts/cm-etcd-manage --kube-cluster "$KUBE_CLUSTER" status
```

`CP_NODE` は API server が動作する対象 CP の BCM 名 / SSH 接続名。管理専用ヘッドを指定しない。etcd status の接続・health・leader・member を確認する。証明書ファイルの欠落だけでは etcd データ破損を示さないため `restore` / メンバー削除は行わない。etcd が不健全ならその結果を別途切り分ける。

#### 2. 欠落・参照先と退避（対象 CP）

```bash
KUBE_CLUSTER='<KUBE_CLUSTER>'
ls -l /etc/kubernetes/pki/"$KUBE_CLUSTER"/apiserver-etcd-client.{crt,key}
ls -l /etc/kubernetes/pki/"$KUBE_CLUSTER"/etcd/ca.crt
ls -l /root/.kube/kubeadm-init-"$KUBE_CLUSTER".yaml
# ローカルで確認し、原文を公開しない
sed -n '1,240p' /etc/kubernetes/manifests/kube-apiserver.yaml
sed -n '1,240p' /root/.kube/kubeadm-init-"$KUBE_CLUSTER".yaml
```

manifest の `--etcd-certfile` / `--etcd-keyfile` / `--etcd-cafile` と `volumeMounts` / `volumes.hostPath` が正しいかを確認する。コンテナとホストで同じパスとは限らない。ホストにファイルがあるなら mount / パスを先に調べ、無条件で証明書を再生成しない。YAML の対象クラスタ、`certificatesDir`、`etcd.external` の endpoint / CA / cert / key、ノード固有 API 設定と実構成を照合する。

変更前に CP の既存 PKI・manifest・kubeadm YAML を退避する。証明書生成の fallback がヘッドのファイルを利用する版があるため、ヘッド側の対象 PKI も同様に退避する。次は対象 CP での例。既存ディレクトリを確認してから実行する。

```bash
umask 077
RECOVERY_DIR=$(mktemp -d /root/k8s-pki-recovery.XXXXXX)
cp -a /etc/kubernetes/pki "$RECOVERY_DIR/"
cp -a /etc/kubernetes/manifests "$RECOVERY_DIR/"
cp -a /root/.kube/kubeadm-init-"$KUBE_CLUSTER".yaml "$RECOVERY_DIR/"
```

退避物には秘密鍵が含まれるため root 専用で保持し、Git へ追加しない。バックアップを static Pod manifest ディレクトリ内に置かない。既存 CA が正しいことを確認できなければ証明書再生成を進めず、BCM の CA と稼働 etcd の信頼設定を照合する。

#### 3. API の可用性による順序（BCM ヘッド）

**API が利用可能で、復旧後の endpoint / BCM 設定へ同期が必要な場合**は、BCM の member 割当を確認してから以下を実行する。`update_configmap` は ConfigMap に加えて各 CP の kubeadm-init YAML を更新するため影響は対象 1 台に限定されない。

```bash
/cm/local/apps/cmd/scripts/cm-kubeadm-manage --kube-cluster "$KUBE_CLUSTER" update_configmap
/cm/local/apps/cmd/scripts/cm-kubeadm-manage --kube-cluster "$KUBE_CLUSTER" update_apiserver "$CP_NODE"
```

**全 API が停止している場合、または設定が既に正しく証明書欠落だけの場合**は、2 の既存 kubeadm-init YAML と CA が現在の実構成に一致していることを前提に、対象 1 台だけ以下を実行する。API 停止中に `update_configmap` を先行させない。

```bash
/cm/local/apps/cmd/scripts/cm-kubeadm-manage --kube-cluster "$KUBE_CLUSTER" update_apiserver "$CP_NODE"
```

この版の `update_apiserver` は、`cm-component-certificate` で対象クラスタの `apiserver-etcd-client.crt` / `.key` を生成し、不足時はヘッドから転送する。リモート CP の etcd CA が欠けていればヘッドから補うが、既存 CA は通常上書きしない。その後対象の kubeadm-init YAML から API manifest を再生成し、crictl で API Pod を停止・削除して kubelet に再作成させる。対象がヘッド自身の場合、CA 転送処理はスキップするため、ヘッド側 CA 欠落を自動で直す手順ではない。

**既存 YAML がない・古い・正否不明の場合は、このコマンドを実行しない。** 証明書と manifest が部分更新され得る。正常 CP / 退避済み設定 / BCM 設定から、ノード固有値も含めて正しい構成を回復する必要がある。他 CP の YAML をそのままコピーしない。

`update_etcd_certs <NODE>` も存在するが、確認した版では既存 etcd CA を `.bak` へ移動（既存 `.bak` は削除）してヘッドの CA を配布し、クライアント証明書・鍵も生成する。CA の上書きを伴うため今回の第一選択にはしない。`update_apiserver_cert` は API のサーバー証明書用、`update_certs` はより広い証明書更新用であり、今回の欠落に対する同義の操作ではない。

#### 4. 復旧確認

対象 CP で以下を確認する。ファイル復旧に加え、CA 検証とコンテナの最新ログを確認する。

```bash
ls -l /etc/kubernetes/pki/"$KUBE_CLUSTER"/apiserver-etcd-client.{crt,key}
openssl verify -CAfile /etc/kubernetes/pki/"$KUBE_CLUSTER"/etcd/ca.crt \
  /etc/kubernetes/pki/"$KUBE_CLUSTER"/apiserver-etcd-client.crt
crictl ps -a --name kube-apiserver
crictl logs --tail=100 <LATEST_APISERVER_CONTAINER_ID>
```

BCM ヘッドで、既存の対象クラスタ管理 kubeconfig を使う。

```bash
kubectl --kubeconfig=/root/.kube/config-"$KUBE_CLUSTER" get --raw='/readyz?verbose'
kubectl --kubeconfig=/root/.kube/config-"$KUBE_CLUSTER" get nodes -o wide
/cm/local/apps/cmd/scripts/cm-etcd-manage --kube-cluster "$KUBE_CLUSTER" status
```

期待結果は証明書の生成・CA 検証成功、API の継続稼働、readyz 成功、Node Ready / Lease 更新の再開。最初の API 復旧後に設定差が判明した場合だけ `update_configmap` と各 CP の `update_apiserver` を 1 台ずつ適用する。ツールが途中失敗した場合は再試行を連続させず、欠落ファイル・部分更新・最新ログを確認する。変更を戻す場合も退避した同一クラスタの対応するファイルを使い、CA / 鍵 / manifest の組を崩さない。etcd snapshot の復元はこの証明書修復には含めない。

### `update_apiserver` に headnode を指定する理由の推測

BCM の headnode と Kubernetes の control-plane は兼任できる役割である。`input/10-bcm-installer-manual/containerization-manual.pdf`（BCM 11、Revision `47eff3c`、2026-09-21）の §4.1 p.28 は headnode または専用ノード上の control plane を説明し、§4.2.8 pp.43–44 は headnode が control-plane / etcd として初期選択されると説明している。紙面と PDF 通しページは一致する。

| 仮説 | 今回の根拠と判断 |
|---|---|
| その案件では headnode も API server を動かしていた | 最有力。専用 CP ノードとは別に「headnode」と列挙していても、Kubernetes 上の役割は CP 兼任の可能性がある。復旧時だけ headnode を CP として使っていた場合も含むが、後者の証拠は未共有 |
| CP 兼任構成の手順が管理専用 headnode の構成へ流用された | headnode が本当に CP でなければ有力。headnode でコマンドを実行することと、引数で headnode を更新対象にすることが混同された可能性もある |
| 別案件の旧版・独自 wrapper に固有の処理がある | コマンド名の表記が異なり、版も未確認のため排除できない。手順原本と実体を確認するまで、本ヘッドの動作だけでは断定できない |

本ヘッドの `update_apiserver <NODE>` は、引数を与えた後にそのノードの CP role を検証する処理がない。headnode 指定でも、対象上の証明書・マニフェスト更新と Pod 再起動を試みる。「headnode を指定すれば全 CP が更新される」「管理専用なので自動でスキップされる」とは扱えない。

次の理由だけで headnode を追加する根拠は確認できなかった。

- **NGINX API プロキシが動いている**: マニュアル §4.1 p.28 は headnode にもプロキシを配置すると説明するが、これは API server 本体とは別で、当該操作は NGINX の設定更新を行わない。
- **etcd member である**: etcd と CP は別の役割なので、etcd だけを動かすノードは API server 更新先とは限らない。
- **kubeconfig・証明書・kubeadm-init YAML がある**: 本ヘッドのセットアップ実装は、最初の CP が別ノードでも headnode に管理用ファイルを配置する。ファイルがあることだけでは CP 兼任の証明にならない。

対象環境での確認は、実効 Kubelet role の `controlPlane`、API server Pod の配置、ノード上の静的 Pod マニフェストと実プロセスを照合する。`kubectl get nodes` のラベル表示だけで決めず、障害時に Pod 情報が古い可能性も考慮する。

以下は **別環境では未実行の読み取り確認例**。BCM ヘッドの root shell で、対象クラスタ用 kubectl / kubeconfig を利用する。`<KUBE_CLUSTER>` は実クラスタ名へ置換する。

```bash
type -a cm-kubeadm-manager cm-kubeadm-manage
/cm/local/apps/cmd/scripts/cm-kubeadm-manage --help
/cm/local/apps/cmd/scripts/cm-kubeadm-manage --kube-cluster <KUBE_CLUSTER> status
kubectl --kubeconfig=/root/.kube/config-<KUBE_CLUSTER> -n kube-system \
  get pods -l component=kube-apiserver -o wide
```

さらに Base View で当該 headnode の Kubelet role、対象 cluster、Control plane の値と割当元 overlay を確認する。headnode 自身では `/etc/kubernetes/manifests/kube-apiserver.yaml` の有無と、対象 container runtime に接続する `crictl ps -a --name kube-apiserver` の結果を確認する。既存ファイルの残骸と稼働中のコンポーネントは区別する。出力の接続先や認証情報は Git 管理外に保持する。

## 5. 復元結果を簡易確認する

API server が再開した後、[`examples/verify-etcd-restore.sh`](examples/verify-etcd-restore.sh) を BCM ヘッドの root shell から実行する。第 1 引数は BCM 上の Kubernetes cluster 名、第 2 引数は検証 namespace 名で、省略時は `default` と `etcd-restore-check`。

```bash
bash docs/examples/verify-etcd-restore.sh <KUBE_CLUSTER> etcd-restore-check
```

`SUMMARY: ... fail=0` と終了コード 0 を合格とする。Pod 一覧は参考情報であり、既存 Job や意図した Pending Pod があり得るため自動合否には含めない。続いてバックアップ前後と復元後の限定 JSON を比較し、Service の `clusterIP`、resource の `uid`、ConfigMap の値を確認する。`resourceVersion` は復旧方式によって revision が変わり得るため、単純一致を必須にしない。

全クラスタの Secrets や ConfigMaps を一括 export すると証跡自体に秘密情報が入るため、比較対象は `etcd-restore-check` namespace に限定する。既存 workload については、利用可能性を別途次のように確認する。

```bash
kubectl get --raw='/readyz?verbose'
kubectl get nodes
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.metadata.creationTimestamp
```

## 6. 証跡採取後に検証リソースを削除する

合否判定と証跡保存が終わった後だけ削除する。namespace の削除自体も etcd へ書き込むため、復元確認前には行わない。

```bash
kubectl delete namespace etcd-restore-check
```

## 残る確認事項

後続の利用者報告として [復旧前後の再起動と Terminating Pod](#復旧前後の再起動と-terminating-pod) を追記した。以下の未構築・未実行の記述は手順作成時点の記録であり、報告対象が本検証クラスタと同一かは未確認である。

- 別環境の BCM、`cmdaemon`、`cm-etcd-manage`、Kubernetes、etcd の版と cluster 名は未共有。
- 別環境の etcd member 数、member / control plane の配置、spool path、snapshot の共有方法は未確認。
- 対象版に一致する BCM multi-member 復旧順は、NVIDIA の公開資料では確認できていない。実リストア前に確定が必要。
- 本リポジトリの Kubernetes は未構築なので、本書の manifest、差分作成、backup、restore、復元確認は未実行。
- PVC / PV と TopoLVM の LV・ファイル内容、外部システムのデータは別の復旧試験が必要。

## 復旧前後の再起動と Terminating Pod

2026-09-25 の利用者報告: etcd 復旧前後にノードを再起動し、`calico-system` の apiserver Pod が `Terminating` に残り、対象 Node の `Non-terminated Pods` にも表示されている。操作日時・正確な実行順・コマンド・出力・製品版は未共有。対象 Node 名は公開可否未確認のため `<TARGET_NODE>` と匿名化し、既存 VM との対応は推定しない。再起動が原因との断定、etcd 復旧成功の判定はしていない。

以下は未実行の案内。既存の管理用 kubeconfig と Pod の照会・削除権限、対象ノードでの root / sudo 権限を前提とする。`Non-terminated Pods` は API 上で phase が Succeeded / Failed 以外の Pod を含み、コンテナが現在動いている証拠ではない。

### 対象と削除待ち理由を確認する

管理端末で実行する。変数の値は実際の対象へ置き換える。Pod 名・UID・割当 Node を記録し、Kubernetes 本体の `kube-system/kube-apiserver-*` と取り違えない。

```bash
kubectl get --raw='/readyz'
kubectl -n calico-system get pods -o wide
CALICO_POD='<対象のTerminating Pod名>'
kubectl -n calico-system get pod "$CALICO_POD" \
  -o jsonpath='{.metadata.uid}{"\n"}{.spec.nodeName}{"\n"}{.metadata.deletionTimestamp}{"\n"}{.metadata.finalizers}{"\n"}{.metadata.ownerReferences}{"\n"}'
kubectl -n calico-system describe pod "$CALICO_POD"
kubectl -n calico-system get deployment,replicaset
```

API が正常に応答し、削除日時が設定済み、終了猶予を過ぎても残ることを確認する。ownerReferences が指す ReplicaSet / Deployment の実在と希望 replica 数も確認する。親がなければ Pod は自動再作成されない。API 自体が不調なら etcd / API の復旧状態を先に確認する。

対象 Node で、設定済みの正しい CRI endpoint を使い、旧 Pod UID に対応する sandbox・コンテナを確認する。

```bash
sudo crictl pods --namespace calico-system
sudo crictl inspectp <照合対象のSANDBOX_ID>
sudo crictl ps -a --pod <UIDが一致したSANDBOX_ID>
sudo journalctl -u kubelet --since '-30 minutes' --no-pager -n 200
```

同名だけで判断せず、inspectp の metadata.uid を API の UID と照合する。取得エラーを「存在しない」と判定しない。旧コンテナが停止済み・存在しないことを確認する。再起動後に再作成された可能性もあるので、再起動した事実だけでは停止確認にならない。稼働中なら kubelet の FailedKillPod、CNI teardown、unmount、API 接続エラーを確認する。ノードに接続できず実体を確認できない場合は、基盤で電源停止を確認してから強制削除を検討する。

### 対象 Pod だけを強制削除する

旧実体が停止済みで、finalizers が空の場合、管理端末で対象 1 Pod を削除する。

```bash
kubectl -n calico-system delete pod "$CALICO_POD" \
  --grace-period=0 --force --wait=false
kubectl -n calico-system get pod "$CALICO_POD"
kubectl -n calico-system get pods -o wide
```

期待結果は旧 Pod が NotFound となり、親 controller が必要数の新 Pod を生成すること。新 Pod の Ready、親 Deployment の Available を確認する。API 上の削除とノード上のプロセス停止は別であり、強制削除は停止完了を待たない。namespace 全体や Calico の DaemonSet を削除する必要はない。[kubectl delete 公式資料](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_delete/)（閲覧日 2026-09-25）を参照。

強制削除後も残る場合は finalizers とコマンドのエラーを再確認する。finalizers がある場合、担当 controller の後処理を確認する。強制削除でも finalizer を自動除去するわけではない。無条件に finalizers を空にせず、キー名・担当 controller・未完了処理を特定する。[Finalizers 公式資料](https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/)（閲覧日 2026-09-25）を参照。Pod が消えても Node の NotReady / CIDRNotAvailable が解消したとは扱わず、[Node の切り分け](kubernetes-cidr-troubleshooting.md) を続ける。

### この追記の実施記録

実施者は Codex、実施日 2026-09-25、時刻は未記録。文書リポジトリで、README、既存 etcd 手順、検証状況、除外設定を git status / cat / sed / tail で確認し、公式の削除・finalizer 資料を Web で参照した。開始時の変更はなく、apply_patch で本節と進捗の参照を追加した。利用者の再起動・障害報告は上記の報告範囲だけを記録した。Codex は対象クラスタへの照会・Pod 削除を実行していない。

保存時は git diff --check、ステージ済み対象一覧・全差分・リンクとコードフェンス、公開情報、input/ の非追跡・除外を確認し、公開用汎用名義でローカルコミットする。証跡は本タスクのツール結果・Git 差分。製品版と原出力が未共有のため、停止原因・削除成功・再作成・Node 復旧は未確認である。

## 2026-09-25: 手順作成の実施記録

実行者は Codex。目的は、別環境で予定する etcd backup / restore 後に Kubernetes resource の復元を簡易判定できる手順を作ること。作業場所は本リポジトリがある BCM 11 ヘッドノードの root shell。Git 管理文書だけを変更し、Kubernetes / etcd / VM への設定変更は行っていない。

1. 開始時の `git status --short --untracked-files=all` が空であることを確認し、README、既存の etcd 調査、要件、検証状況、製品資料索引を読んだ。
2. インストール済み `/cm/local/apps/cmd/scripts/cm-etcd-manage` の backup / restore 実装と各 `--help` を読み取り確認した。`--help` は sandbox で `/var/log/cm-etcd-manage.log` を開けない警告を表示したが、構文確認は完了した。backup、restore、status は実行していない。
3. NVIDIA の DGX 更新手順、Kubernetes の etcd 運用手順、etcd 3.5 の disaster recovery 資料を確認した。NVIDIA 公開資料では backup 例を確認したが、BCM multi-member cluster の完全な restore 順は確認できなかった。
4. `kubectl` と `shellcheck` は本ヘッドの `PATH` になく、manifest の server / client dry-run と ShellCheck は実行できなかった。PyYAML 6.0.1 は利用可能だった。これらを実クラスタでの未実行事項と区別する。
5. `bash -n` で検証スクリプトの構文を確認した。PyYAML で manifest を読み、想定した 5 document の kind / name と Deployment の replica 0 を確認した。変更文書の相対リンク先、`git diff --check`、テキスト形式と file mode も確認し、いずれも問題はなかった。
6. ステージした 8 ファイルの全差分と公開情報を確認した。検出された `Secret` は snapshot と証跡の保護を求める一般説明だけで、実値はなかった。実接続情報、認証情報、個人・組織情報、第三者資料の転載、画像、バイナリは含まれない。`input/` の追跡ファイルはなく、除外設定も有効だった。既定の Git identity には公開に適さないホスト識別情報が含まれたため、コミット時は公開用の `Codex <codex@openai.com>` を明示して使用する。

期待結果は、復元前後を識別でき、秘密情報を含む全クラスタ export を必要としない簡易判定を定義すること。実際の結果は、専用 namespace と限定 resource による正負の判定条件、読み取り専用の検証スクリプト、安全停止条件を文書化した。実リストアの成功を示す結果ではない。

## 2026-09-25: kubeadm 設定整合と headnode 指定の追加調査記録

- 実行者: Codex。ユーザーからは別案件の手順の存在だけが共有され、その環境で今回コマンドを実行したとの報告はない。
- 目的・対象: 復元後の両 update 操作の説明と headnode 指定の理由の推測。本リポジトリがある BCM ヘッドでの読み取りと文書更新が対象。更新コマンド・クラスタへの照会は実行しない。
- 実施時刻: 個別操作の全時刻は未記録。ヘルプ照会と `date --iso-8601=seconds` は 14:26:39–14:26:40 JST。
- 版: `cmdaemon` は `11.0-165270-cm11.0-14a0291f4f`、`cm-setup` は `11.0-124257-cm11.0-7f8393643d`。対象の `/cm/local/apps/cmd/scripts/cm-kubeadm-manage` は 41,879 bytes、mode 700、mtime 2026-09-10 01:22:14 JST、SHA-256 `5f30f868d3fde2b1123a4953bc0507d1c68c0acfc8a1d7641a23371748624427`。

実行順と結果:

1. `git status --short --untracked-files=all` で開始時の変更がないことを確認し、README、AGENTS、既存 etcd 手順、製品資料索引、関連文書を読んだ。`command -v cm-kubeadm-manager` は出力なし。`rg --files` で末尾が `manage` の実体を発見し、`stat`、`dpkg-query -S` / `-W`、`sha256sum` でファイルと所有パッケージを確認した。コマンド名や関連語の検索で終了 1 となった箇所は該当なしとして扱った。
2. `rg -n`、`sed -n`、`nl -ba` で実体の `get_master_data`（75–110 行）、`get_expected_endpoints`（262–286 行）、`update_configmap`（309–585 行）、`update_apiserver`（588–590 行）、`update_control_plane_component`（655–686 行）、証明書処理（689–766 行）、引数・dispatch（842–919 行）を読んだ。BCM role、ConfigMap、ノード上ファイル、API server Pod の依存関係を確認した。原本のソースコードは転載しない。
3. `/cm/local/apps/cm-setup/lib/python3.12/site-packages/cmsetup/plugins/kubernetes/stages/kubeadm.py` の初期 CP 選定と headnode への管理用ファイル配置処理を読んだ。headnode に kubeadm-init YAML があるだけでは CP と判定できないことを確認した。既存 etcd 復旧処理も読み取り参照した。
4. `PYTHONPATH=/tmp/bcm-pdf-read python3` と pypdf で上記 Containerization Manual を検索した。対象コマンド名・両 subcommand の本文検索は 0 件。表紙、§4.1 p.28、§4.2.8 pp.43–44 は headnode の役割・NGINX・初期選択の根拠として読んだ。
5. NVIDIA の [BCM 11 Release Notes](https://docs.nvidia.com/base-command-manager/bcm-11-release-notes/overview.html) と [DGX 更新手順](https://docs.nvidia.com/dgx-superpod/update-guide/latest/kubernetes-updates.html)、Kubernetes の [再設定手順](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/) と [kubeadm init phase](https://kubernetes.io/docs/reference/setup-tools/kubeadm/kubeadm-init-phase/) を閲覧した。DGX ページの BCM KB リンクは閲覧ツールが Internal Error を返し、該当 KB の内容は確認できなかった。関連語の Web 検索でも両操作の別案件手順を取得できなかった。
6. 絶対パスで `--help`、`--kube-cluster default update_apiserver --help`、`--kube-cluster default update_configmap --help` を実行した。いずれも終了 0、ログ先が読み取り専用という警告あり。引数の解釈段階で終了するヘルプだけを確認し、更新処理も `status` も実行していない。
7. 本書へ上記説明・推測・未実行の確認方法を追記し、README の索引と製品資料索引を更新した。Python で変更した 3 文書の相対リンク・見出しアンカー・コードフェンス・末尾改行を確認し、`git diff --check` とあわせて成功した。
8. [既存の保存前手順](repository-maintenance.md#保存前の確認コミット手順) で対象 3 文書をステージし、対象一覧・全差分・空白エラー・作業ツリーとの一致・公開情報の補助検索を確認した。`input/` の追跡はなく、対象 PDF は除外されていた。環境文書のパスワードは既存のプレースホルダーを維持している。追加内容は操作の独自説明、公式 URL、公開製品の版・ファイル識別情報で、認証情報・実接続情報・第三者原本の転載はなく、削除・匿名化を要する問題はなかった。追記後にも再ステージして確認する。コミットは公開用の `Codex <codex@openai.com>` を使用し、ID と残変更は完了報告に記す。

期待結果は、確定できる挙動と案件依存の推測を切り分けること。実際には、ConfigMap / ローカル YAML / static Pod の更新範囲と、headnode を全 CP 更新の代表引数とは扱えないことを確認した。証跡は本タスクのツール出力、上記ファイル・版・行番号、一次 PDF の該当ページ、公式 URL、Git 差分。別案件の正確なコマンド実体、role、実行順、実行結果は未確認。本環境の構成・検証進捗に変更はない。

## 2026-09-25: etcd クライアント証明書欠落の復旧手順調査

実施者は Codex。目的は利用者が crictl で確認した証明書欠落に対する BCM コマンドの手順化。文書リポジトリと本ヘッドのインストール済みスクリプトを読み取り、文書と Git だけを変更した。障害環境の修復操作は未実施。ユーザーのログ確認は報告として上記に記録し、時刻・正確なコマンド・原出力は未記録とした。

実行順と結果:

1. `git status --short --untracked-files=all` は変更なし。README、etcd 管理・復旧・製品資料・環境の関連節を `cat` / `sed` / `rg` で確認した。大きい出力は省略があり、必要な実装説明を個別に再取得した。
2. 本ヘッドの `/cm/local/apps/cmd/scripts/cm-kubeadm-manage` を `rg` / `sed` で確認。行 588–590、655–766、842–915 の更新・証明書生成・配布・dispatch と、309–329 の API 依存を確認した。`cm-etcd-manage` の引数定義も確認。第三者の実装原文は文書に転載せず、必要な動作を要約した。
3. `dpkg-query -W` で `cmdaemon 11.0-165270-cm11.0-14a0291f4f`、`cm-setup 11.0-124257-cm11.0-7f8393643d` を確認。両ツールへ `--kube-cluster placeholder` を渡し、`update_apiserver --help`、`update_etcd_certs --help`、`status --help` を実行した。ヘルプ表示に成功。`/var/log` が読み取り専用でログ出力の警告があったが console 表示された。引数解析で終了するヘルプだけで、status 本体・生成・配布・再起動は実行していない。
4. Web で NVIDIA BCM 11 Release Notes と関連公式情報を確認。ツールの役割は [BCM 11 Release Notes](https://docs.nvidia.com/base-command-manager/bcm-11-release-notes/overview.html)（2026-09-25 閲覧）、正確な処理・引数は上記ローカル実装を根拠とした。ユーザーの追加回答は BCM 11.33・CP 1 台稼働。障害環境のパッケージ版と実装同一性は未確認。
5. Python で本書の条件付き復旧手順、切り分け文書への導線、検証状況を更新。差分、コードブロック・相対リンク、ステージ済み内容・公開情報、input の非追跡と除外を確認し、公開用汎用名義でコミットする。対象は 3 文書、証跡は本タスクのツール出力と Git 差分。公開・push と過去履歴全体の監査は対象外。

期待結果は API 可用性と既存設定の正しさに応じた復旧順の提示。実際の成果は上記手順の保存とユーザー報告の反映。実環境識別子はプレースホルダーへ置換し、秘密鍵・証明書の実値や第三者資料原本は追加していない。BCM 11.33 の実パッケージ版・対象 CP・ホスト上のファイル / mount・既存 CA / YAML・実修復結果は未確認。コミット ID・公開チェック結果・残変更は完了報告に記載する。
