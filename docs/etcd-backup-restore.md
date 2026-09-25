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

- 別環境の BCM、`cmdaemon`、`cm-etcd-manage`、Kubernetes、etcd の版と cluster 名は未共有。
- 別環境の etcd member 数、member / control plane の配置、spool path、snapshot の共有方法は未確認。
- 対象版に一致する BCM multi-member 復旧順は、NVIDIA の公開資料では確認できていない。実リストア前に確定が必要。
- 本リポジトリの Kubernetes は未構築なので、本書の manifest、差分作成、backup、restore、復元確認は未実行。
- PVC / PV と TopoLVM の LV・ファイル内容、外部システムのデータは別の復旧試験が必要。

## 2026-09-25: 手順作成の実施記録

実行者は Codex。目的は、別環境で予定する etcd backup / restore 後に Kubernetes resource の復元を簡易判定できる手順を作ること。作業場所は本リポジトリがある BCM 11 ヘッドノードの root shell。Git 管理文書だけを変更し、Kubernetes / etcd / VM への設定変更は行っていない。

1. 開始時の `git status --short --untracked-files=all` が空であることを確認し、README、既存の etcd 調査、要件、検証状況、製品資料索引を読んだ。
2. インストール済み `/cm/local/apps/cmd/scripts/cm-etcd-manage` の backup / restore 実装と各 `--help` を読み取り確認した。`--help` は sandbox で `/var/log/cm-etcd-manage.log` を開けない警告を表示したが、構文確認は完了した。backup、restore、status は実行していない。
3. NVIDIA の DGX 更新手順、Kubernetes の etcd 運用手順、etcd 3.5 の disaster recovery 資料を確認した。NVIDIA 公開資料では backup 例を確認したが、BCM multi-member cluster の完全な restore 順は確認できなかった。
4. `kubectl` と `shellcheck` は本ヘッドの `PATH` になく、manifest の server / client dry-run と ShellCheck は実行できなかった。PyYAML 6.0.1 は利用可能だった。これらを実クラスタでの未実行事項と区別する。
5. `bash -n` で検証スクリプトの構文を確認した。PyYAML で manifest を読み、想定した 5 document の kind / name と Deployment の replica 0 を確認した。変更文書の相対リンク先、`git diff --check`、テキスト形式と file mode も確認し、いずれも問題はなかった。
6. ステージした 8 ファイルの全差分と公開情報を確認した。検出された `Secret` は snapshot と証跡の保護を求める一般説明だけで、実値はなかった。実接続情報、認証情報、個人・組織情報、第三者資料の転載、画像、バイナリは含まれない。`input/` の追跡ファイルはなく、除外設定も有効だった。既定の Git identity には公開に適さないホスト識別情報が含まれたため、コミット時は公開用の `Codex <codex@openai.com>` を明示して使用する。

期待結果は、復元前後を識別でき、秘密情報を含む全クラスタ export を必要としない簡易判定を定義すること。実際の結果は、専用 namespace と限定 resource による正負の判定条件、読み取り専用の検証スクリプト、安全停止条件を文書化した。実リストアの成功を示す結果ではない。
