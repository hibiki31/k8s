# Kubernetes の `CIDRNotAvailable` / `NotReady` 切り分け

2026-09-25 に利用者から、Kubernetes コントロールプレーンが `CIDRNotAvalible` と表示され、`NotReady` になっているとの報告を受けた。チャット上の綴りは Kubernetes の正式なイベント理由 `CIDRNotAvailable` を指すものとして本書を整理する。本書は、原因を確定する前に行う読み取り専用の切り分けと、更新停止時の条件付き復旧手順をまとめる。利用者から元のイベント、Node condition、ログ、Kubernetes 版、採用 CNI、Pod CIDR / Service CIDR はまだ共有されていないため、イベント理由の実表記、障害原因、復旧方法は未確定である。

表示名の正式な綴りは `CIDRNotAvailable`。Kubernetes の RangeAllocator 実装では、Node に割り当てる CIDR を `AllocateNext()` で取得できないときに、この理由のイベントを記録する。一方、Node の `Ready=False` / `Unknown` は kubelet が報告する別の状態である。したがって、`CIDRNotAvailable` が同じ時刻に出たという理由だけで、`NotReady` の直接原因と断定しない。

## 対象・前提・安全条件

- 対象は BCM の `cm-kubernetes-setup` が kubeadm を使って構築する本検証クラスタ。本環境の BCM インストールメディアは 11.34.0 だが、稼働中の BCM パッケージ版、Kubernetes 版、基本 CNI は今回未確認である。
- 本検証の目標構成はコントロールプレーン 3 台・ワーカー 3 台。Node CIDR は、Pod を配置しない taint 付きコントロールプレーンにも割り当てられる場合があるため、容量計算は API に登録された全 Node を対象にする。
- `kubectl` は、既存の管理用 kubeconfig が設定された BCM ヘッドノードまたは管理端末で実行する。kubeconfig には認証情報が含まれるため、内容を Git 管理文書や共有ログへ転載しない。
- OS コマンドは明記したコントロールプレーンまたは BCM ヘッドノードで実行する。最初は読み取り専用の確認だけを行い、`kubeadm reset`、クラスタ再作成、Node 削除、static Pod manifest の編集、CNI の再適用、サービス再起動は行わない。
- 生のログと YAML には IP、ホスト名、接続先、証明書情報などが含まれ得る。原本は Git 管理外の `input/80-kubernetes-cidr/` などに保存し、公開文書には必要な要点だけを匿名化して記録する。

## 最初に判定すること

| 観測 | 主に疑う範囲 | 次に進む節 |
|---|---|---|
| 対象 Node の `spec.podCIDR` が空で、`CIDRNotAvailable` が反復し、controller-manager に `failed to allocate cidr` / `no remaining CIDRs` がある | Pod CIDR の容量不足、Service CIDR との重複、dual-stack の片系枯渇 | [CIDR 設計と割り当て](#3-cidr-設計と割り当てを照合する) |
| `spec.podCIDR` は一意に割り当て済みで、`Ready=False` のメッセージが `NetworkPluginNotReady` や CNI 未初期化を示す | 基本 CNI、CNI 設定・バイナリ、container runtime | [NotReady の直接原因](#4-notready-の直接原因をノード側で確認する) |
| `Ready=Unknown` / `NodeStatusUnknown`、Lease 更新も停止 | kubelet 停止、API endpoint への到達性、時刻・証明書 | [NotReady の直接原因](#4-notready-の直接原因をノード側で確認する) |
| `CIDRAssignmentFailed` であり `CIDRNotAvailable` ではない | Node オブジェクト更新失敗、API timeout / 認可 | controller-manager ログと API の状態 |
| controller-manager が CrashLoop、既存 Node の Pod CIDR が現在の cluster CIDR 外 | CIDR 設定変更後の不整合、壊れた・古い Node 情報 | [設定の一致](#2-controller-manager-の設定とログを確認する) |

## 1. Node condition・イベント・Pod CIDR を同じ時点で採取する

### 1.1 クラスタ全体と対象 Node

既存の kubeconfig を使える場所で実行する。`<CONTROL_PLANE_NODE>` は実際の Kubernetes Node 名へ置き換える。イベントは保持期間を過ぎると消えるため、最初に採取する。

```bash
date -Is
kubectl version --output=yaml
kubectl get nodes -o wide
kubectl get nodes \
  -o custom-columns='NAME:.metadata.name,PODCIDR:.spec.podCIDR,PODCIDRS:.spec.podCIDRs,TAINTS:.spec.taints[*].key'
kubectl get node <CONTROL_PLANE_NODE> \
  -o jsonpath='{range .status.conditions[*]}{.type}{"\t"}{.status}{"\t"}{.reason}{"\t"}{.message}{"\t"}{.lastTransitionTime}{"\n"}{end}'
kubectl describe node <CONTROL_PLANE_NODE>
kubectl get events -A \
  --field-selector involvedObject.kind=Node,involvedObject.name=<CONTROL_PLANE_NODE> \
  --sort-by=.metadata.creationTimestamp
```

確認点:

1. `Ready` が `False` か `Unknown` か、`Reason` と `Message` は何か。
2. `CIDRNotAvailable` の `Source` / `From`、最初と最後の発生時刻、反復回数。
3. 対象 Node の `spec.podCIDR` / `spec.podCIDRs` が空か。全 Node の値が重複せず、意図した Pod CIDR 内にあるか。
4. 期待する 6 台以外の古い Node オブジェクトが残っていないか。`NotReady` の古い Node も割り当て済み CIDR を占有し得る。
5. `NetworkUnavailable`、`MemoryPressure`、`DiskPressure`、`PIDPressure` と taint。`Ready` だけを見て CNI 障害と決めない。

### 1.2 kubelet の更新停止を区別する

`Ready=Unknown` または `NodeStatusUnknown` の場合は、対象 Node の Lease 更新時刻も確認する。

```bash
kubectl -n kube-node-lease get lease <CONTROL_PLANE_NODE> -o yaml
```

Lease も更新されていなければ、CIDR 枯渇より先に kubelet、Node から API endpoint への疎通、時刻同期を確認する。Lease が更新中で `Ready=False` なら、kubelet の `Message` に示された runtime / CNI / resource pressure を追う。

## 2. controller-manager の設定とログを確認する

### 2.1 稼働 Pod・leader・ログ

管理用の `kubectl` 実行場所で、3 台分の controller-manager と現在の leader を確認する。

```bash
kubectl -n kube-system get pods -l component=kube-controller-manager -o wide
kubectl -n kube-system get lease kube-controller-manager -o yaml
kubectl -n kube-system logs -l component=kube-controller-manager \
  --all-containers=true --prefix --since=2h --tail=-1 \
  | grep -Ei 'CIDRNotAvailable|CIDRAssignmentFailed|failed to allocate cidr|no remaining CIDR|node.?ipam|cluster.?cidr|service.?cidr'
```

ラベル選択で Pod が得られない場合は `kubectl -n kube-system get pods -o wide` で実名を確認し、各 controller-manager Pod を指定して `kubectl logs` を実行する。HA 構成では leader のログを必ず含める。次を区別する。

- `failed to allocate cidr from cluster cidr` / CIDR が残っていない: 割り当て可能ブロックの不足。
- `failed to mark ... as occupied` / CIDR が範囲外: 既存 Node の `podCIDRs` と現在の設定の不一致。
- `Failed to update node PodCIDR` と `CIDRAssignmentFailed`: API への更新失敗。単純な CIDR 枯渇とは別。
- dual-stack の `idx:0` / `idx:1`: どちらのアドレスファミリーで失敗したかを、flag の順序と照合する。

API 経由の `kubectl logs` が取得できない場合は、**各コントロールプレーン**で runtime 内の container ID を確認してログを読む。`<CONTAINER_ID>` は直前の一覧に出た controller-manager の ID へ置き換える。

```bash
sudo crictl ps -a --name kube-controller-manager
sudo crictl logs <CONTAINER_ID>
```

### 2.2 3 台の static Pod manifest を比較する

**各コントロールプレーン**で、同じコマンドを実行する。ここでは表示だけを行い、ファイルを編集しない。

```bash
sudo grep -E -- \
  '--(allocate-node-cidrs|cluster-cidr|node-cidr-mask-size|node-cidr-mask-size-ipv4|node-cidr-mask-size-ipv6|service-cluster-ip-range)' \
  /etc/kubernetes/manifests/kube-controller-manager.yaml
sudo grep -E -- '--service-cluster-ip-range' \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

確認点:

- `--allocate-node-cidrs=true` の有無。
- `--cluster-cidr` と per-node の mask size。flag が省略されている場合は、対象 Kubernetes 版の既定値を公式資料で確認する。
- IPv4 / IPv6 の順序と本数。
- `--service-cluster-ip-range` が Pod CIDR と重複していないか。
- 3 台の値が一致するか。leader 交代時だけ症状が変わるなら、manifest の差を疑う。

kubeadm が保存した構築時設定も参照する。これは現在の static Pod manifest と一致する保証はないため、正本と決めつけず差分を確認する。

```bash
kubectl -n kube-system get configmap kubeadm-config \
  -o jsonpath='{.data.ClusterConfiguration}' \
  | grep -E 'podSubnet|serviceSubnet'
```

### 2.3 BCM の構築時入力とログを照合する

**BCM ヘッドノード**で実行する。BCM 11 Containerization Manual はセットアップログを `/var/log/cm-kubernetes-setup.log` としている。

```bash
sudo test -r /var/log/cm-kubernetes-setup.log
sudo grep -Ei \
  'pod.*(network|cidr)|service.*(network|cidr)|cluster.?cidr|node.?cidr|calico|flannel|error|fail' \
  /var/log/cm-kubernetes-setup.log
```

ウィザードに入力した Pod / Service ネットワーク、選択した基本 CNI、構築時エラーを、現在の kubeadm ConfigMap と各 controller-manager manifest に照合する。ログ全体は認証情報・接続情報を確認してから扱い、Git へ追加しない。

## 3. CIDR 設計と割り当てを照合する

### 3.1 容量

IPv4 の cluster CIDR の prefix を `C`、Node ごとの prefix を `N` とすると、理論上の Node 用ブロック数は `2^(N-C)`。実際には Service CIDR との重複、既存 Node の割り当て、dual-stack の各アドレスファミリーを考慮する。

| cluster CIDR | per-node CIDR | 理論上のブロック数 | 6 Node への評価 |
|---|---:|---:|---|
| `/24` | `/24` | 1 | 不足 |
| `/22` | `/24` | 4 | 不足 |
| `/21` | `/24` | 8 | 理論上は収容可能だが余裕は 2 Node 分 |
| `/16` | `/24` | 256 | 容量上は十分。重複と CNI 設定を別途確認 |

`/21` を採用するという指定ではない。必要 Pod 数、将来の Node 追加、CNI の IPAM / block size、既存ネットワークとの非重複を満たす値を選ぶ。本クラスタの 6 台だけを想定しても、コントロールプレーンを計算から除外しない。

### 3.2 重複と不整合

少なくとも次の範囲を一覧化し、包含・交差がないことを確認する。

- Pod CIDR と Service CIDR。
- 本環境の内部ノードネットワーク `172.30.65.0/24` と外部ネットワーク `172.30.64.0/24`。
- Multus 用のセカンダリネットワーク（現在の公開文書では IP 範囲未確定）。
- 仮想化ホスト、BCM、管理端末、接続先環境で経路を持つネットワーク。
- CNI 固有の IP pool / block size と controller-manager の cluster CIDR / node mask。

現行 Kubernetes の RangeAllocator 実装は、Service CIDR が cluster CIDR と重なる場合に該当範囲を使用済みとして除外する。対象版の実装差はあり得るが、Pod CIDR と Service CIDR の重複はいずれにせよ解消対象とする。

### 3.3 古い Node と変更履歴

`kubectl get nodes` の全行を、BCM の役割割り当てと VM 一覧に照合する。再構築前の同名・別名 Node、廃止 VM、誤って追加した Node が残る場合は、その `spec.podCIDR(s)` も確認する。

controller-manager の `--cluster-cidr` または node mask を構築後に変更した履歴がある場合は、既存 Node の割り当てが新しい範囲外になっていないか確認する。Node の `spec.podCIDR` だけを手作業で書き換えると、CNI の IPAM、経路、既存 Pod IP と不整合になるため、復旧方法として採用しない。

## 4. `NotReady` の直接原因をノード側で確認する

### 4.1 kubelet・container runtime・基本 CNI

**対象コントロールプレーン**で実行する。サービス名が異なる場合は、実環境の runtime 名に読み替える。

```bash
sudo systemctl is-active kubelet containerd
sudo systemctl --failed
sudo journalctl -u kubelet --since '-2 hours' --no-pager -n 500
sudo journalctl -u containerd --since '-2 hours' --no-pager -n 300
sudo crictl info
sudo crictl ps -a
sudo ls -la /etc/cni/net.d /opt/cni/bin
```

確認点:

- `NetworkPluginNotReady`、`cni plugin not initialized`、CNI 設定なし、CNI バイナリなし。
- Pod sandbox 作成失敗、CNI 設定の parse / version error、IPAM の割り当て失敗。
- container runtime の停止、CRI endpoint 不一致、kubelet の起動失敗。
- swap、証明書、時刻ずれ、ディスク枯渇など、CIDR 以外の kubelet 起動阻害要因。

クラスタ側でも基本 CNI の DaemonSet / Pod を特定する。

```bash
kubectl -n kube-system get daemonset,deployment,pod -o wide
kubectl -n kube-system describe pod <CNI_POD>
kubectl -n kube-system logs <CNI_POD> --all-containers=true --since=2h
```

Calico / Flannel のどちらを BCM で選択したかを先に確定する。Multus は基本 CNI に追加するメタプラグインであり、基本 CNI が未導入・異常な状態の代替にはしない。

### 4.2 `Ready=Unknown` の場合

対象 Node で次を確認し、kubelet の停止と API 到達不能を区別する。`<API_ENDPOINT>` は kubelet 設定が参照する実際の endpoint、`<API_PORT>` は実際の port に置き換える。

```bash
timedatectl status
ip -brief address
ip route
getent hosts <API_ENDPOINT>
nc -vz <API_ENDPOINT> <API_PORT>
sudo systemctl status kubelet --no-pager
```

API 疎通が失敗する場合は、本環境の内部ネットワーク、BCM 経由の DNS / routing、firewall を確認する。到達できる場合は kubelet ログの証明書・認証・Node 名不一致を確認する。全コントロールプレーンで同時にサービスを再起動せず、原因と影響範囲を確定してから復旧計画を作る。

### 4.3 `Kubelet stopped posting node status` の確認と条件付き復旧

このメッセージは状態更新が途絶えたことを表し、kubelet プロセス停止そのものを確定しない。API 到達性・認証失敗・ノード停止でも起こり得る。以下は **未実行の手順**。systemd を使う Linux が前提で、管理端末には Node / Lease の読み取り権限、対象ノードには sudo 権限が必要。`<...>` は実値を伏せたプレースホルダーで、実行時に置き換える。

1. **管理用 kubectl の実行場所**で対象と更新時刻を確認する。

   ```bash
   NODE='<NODE_NAME>'
   kubectl get nodes -o wide
   kubectl describe node "$NODE"
   kubectl -n kube-node-lease get lease "$NODE" -o jsonpath='{.spec.renewTime}{"\n"}'
   ```

2. **NotReady の対象ノードに SSH またはコンソールで接続**し、再起動前にログを採取する。

   ```bash
   date -Is
   sudo systemctl status kubelet --no-pager -l
   sudo journalctl -u kubelet --since '-30 minutes' --no-pager -n 200
   sudo systemctl status containerd --no-pager -l
   sudo journalctl -u containerd --since '-30 minutes' --no-pager -n 100
   df -h
   df -i
   free -h
   swapon --show
   timedatectl status
   ```

   `status` の非ゼロ終了は停止・失敗を表す場合があるため、後続のログ確認も行う。containerd は採用している場合だけ確認し、別 runtime は実際のサービス名に読み替える。サービスが見つからなければ `systemctl list-unit-files --type=service | grep -Ei 'kubelet|containerd|crio|cri-o'` で配置を確認する。SSH 不可の場合は仮想化ホストから VM の電源・コンソール・ネットワークを先に確認する。

3. **kubelet が停止・失敗している場合**は、ログの設定不備・容量不足などを解消してから、対象 1 台だけ起動し直す。意図的なメンテナンス停止中でないことを確認する。

   ```bash
   sudo systemctl restart kubelet
   sudo systemctl status kubelet --no-pager -l
   sudo journalctl -u kubelet --since '-5 minutes' --no-pager -n 100
   ```

   containerd も停止していて、それが採用 runtime である場合のみ、先に `sudo systemctl start containerd` を実行して active を確認する。稼働中の runtime の一律再起動は行わない。コントロールプレーンは 1 台ずつ扱い、すぐ失敗を繰り返す場合はログの原因修正に戻る。

4. **kubelet が active でも更新しない場合**は、対象ノードから kubelet の実際の API 接続先を確認する。`sudo systemctl cat kubelet` の起動設定から `--kubeconfig` のパスを確認する（出力は公開しない）。kubeadm の標準パスの場合、接続先の行だけ表示する例は次のとおり。

   ```bash
   sudo grep -E '^[[:space:]]*server:' /etc/kubernetes/kubelet.conf
   getent hosts '<API_HOST>'
   nc -vz -w 5 '<API_HOST>' <API_PORT>
   ```

   `<API_HOST>` は URL のホスト部分、`<API_PORT>` はそのポートで、6443 と決めつけない。`nc` が未導入なら別途利用可能な TCP 確認手段を使う。TCP 接続成功だけでは TLS・認証・API 健全性は証明できない。管理用端末の `kubectl get --raw='/readyz?verbose'` も API 側の切り分けに使えるが、対象ノードの経路・資格情報の正常性は証明しない。

| kubelet ログの例 | 次の確認・修復 |
|---|---|
| `connection refused` / `i/o timeout` / `no route to host` | API 待受、LB、DNS、経路、firewall。kubelet 再起動だけでは直らない |
| `x509` / `expired` / `not yet valid` | 時刻同期と実際のクライアント・サーバー証明書の期限。証明書を一括削除・再生成しない |
| `Unauthorized` / `Forbidden` | kubelet の認証情報と Node 名・認可の整合性 |
| `running with swap on is not supported` | swap を拒否する構成か確認。メモリ余裕を確認して swap 無効化し、BCM の永続設定も整合させる |
| `no space left on device` / OOM | ディスク・inode・メモリ不足。データを無差別削除せず原因を解消 |
| `NetworkPluginNotReady` | 更新再開後の別の NotReady 原因として 4.1 の CNI 確認に進む |

5. **管理用 kubectl の実行場所**で復旧確認する。

   ```bash
   kubectl wait --for=condition=Ready "node/$NODE" --timeout=180s
   kubectl get node "$NODE" -w
   # 数分観察後に Ctrl-C
   kubectl -n kube-node-lease get lease "$NODE" -o jsonpath='{.spec.renewTime}{"\n"}'
   ```

   期待結果は `Ready=True` の継続、Lease の更新再開、ログで更新失敗が反復しないこと。timeout は未復旧として記録する。Pod や CNI の動作は別途確認し、Node Ready だけでクラスタ全体の復旧完了にしない。

## 5. 観測結果から原因を確定する

| 証拠の組み合わせ | 判定 | 復旧方針 |
|---|---|---|
| 後から登録した Node だけ Pod CIDR が空、`CIDRNotAvailable` 反復、ログに空きなし | cluster CIDR が Node block 数に対して小さい | Pod 数・将来増設を含む CIDR を再設計。構築直後の廃棄可能クラスタなら BCM の対応手順で再作成を優先 |
| Pod / Service CIDR が重複 | アドレス設計不整合 | 片方を別範囲へ移す計画を作成。稼働中の一部 flag だけを変更しない |
| dual-stack の一方だけ空きなし | 片方の family の容量不足または mask 不一致 | 両 family の cluster CIDR、node mask、CNI 対応を揃えて再設計 |
| 期待外の古い Node が CIDR を保持 | stale Node オブジェクト | 対象が稼働しておらず必要データもないことを確認後、Node 削除の変更手順を別途承認・実施 |
| 全 Node に一意の Pod CIDRあり、kubelet が CNI 未初期化 | CNI の配置・設定・runtime 読み込み | 選択した CNI の DaemonSet、設定ファイル、バイナリ、イメージ取得を修復 |
| `Ready=Unknown`、Lease 停止 | kubelet / API 到達性 | kubelet、時刻、証明書、内部ネットワーク、API endpoint を修復 |
| 3 台の controller-manager flag が不一致 | HA control plane の構成差 | BCM / kubeadm の管理方法を確認し、同一設定へ統一。個別の場当たり編集は避ける |

## 6. 変更を伴う復旧へ進む条件

復旧前に、etcd バックアップ、現在の manifest、kubeadm ConfigMap、CNI 設定、全 Node の YAML、BCM セットアップログを採取し、対象版と復旧経路を決める。etcd の手順は [BCM etcd バックアップ・リストア試験](etcd-backup-restore.md) を参照するが、同書は本環境で未実施であり、バックアップ取得済みとは扱わない。

- **構築直後で破棄可能、CIDR 設計が誤り**: BCM の対象版でサポートされる削除・再構築方法を確認し、修正した Pod / Service CIDR と基本 CNI でクラスタを作り直す。途中状態の Node CIDR を手編集するより再現性が高い。
- **稼働データがある**: `--cluster-cidr`、kube-proxy、CNI IP pool、Node の割り当て、既存 Pod IP / route を一体として扱う移行計画が必要。static Pod manifest の一部だけを変更しない。
- **stale Node が原因**: VM・BCM・Kubernetes の対応とワークロード / ローカルデータ不在を確認した後にのみ削除する。Node 削除は変更操作なので、本切り分け手順には実行済みとして含めない。
- **CNI が原因**: BCM が選択・配置した基本 CNI の版と設定を基準に修復する。原因確認前に別 CNI や Multus を重ねて導入しない。
- **controller-manager の設定差**: 3 台を一度に変更・再起動しない。対象 Kubernetes / BCM 版の再設定方法、API / etcd の健全性、ロールバック方法を確定してから 1 台ずつ扱う。

## 7. 復旧後の確認条件

次をすべて確認し、`CIDRNotAvailable` が消えただけで完了にしない。

1. 期待する 6 Node が登録され、全 Node の `Ready=True` が継続する。
2. 各 Node の `spec.podCIDR(s)` が意図した範囲内で一意。空欄・重複・範囲外がない。
3. controller-manager 3 台の CIDR 関連 flag が一致し、leader 交代後も新しい割り当てエラーがない。
4. 基本 CNI の DaemonSet が期待数 Ready、CoreDNS 等の `kube-system` Pod が正常。
5. 修復後の時刻以降に `CIDRNotAvailable` / `CIDRAssignmentFailed` が反復していない。
6. テスト Pod の IP が対象 Node の Pod CIDR に含まれ、同一 Node・Node 間の Pod 通信、Service 経由の通信、DNS が成功する。
7. コントロールプレーン 1 台ずつの再起動後にも kubelet、CNI、Node Ready、CIDR 割り当てが維持される。再起動試験は API / etcd の冗長性とロールバック方法を確認してから行う。

## まず共有する最小限の証跡

原因を絞るには、次の出力を秘密情報と実環境識別情報を確認・匿名化して共有する。

1. `kubectl version --output=yaml` と `kubectl get nodes -o wide`。
2. 全 Node の `spec.podCIDR(s)` 一覧。
3. 対象 Node の Conditions と Node イベント。
4. 3 台それぞれの controller-manager の CIDR 関連 flag。
5. controller-manager の該当時刻の CIDR エラー。
6. `kube-system` の CNI Pod 一覧と、対象 Node の kubelet ログにある最初の失敗。
7. BCM で選択した基本 CNI、Pod CIDR、Service CIDR（公開可否未確認なら匿名化した prefix 長と重複関係だけでも可）。

## 根拠資料

- [Kubernetes 1.34.0 の RangeAllocator 実装](https://github.com/kubernetes/kubernetes/blob/v1.34.0/pkg/controller/nodeipam/ipam/range_allocator.go): `AllocateNext()` 失敗時の `CIDRNotAvailable`、既存 Node CIDR の占有、Service CIDR との重複除外。本環境の採用版は未確認なので、実クラスタの tag とも照合する。
- [kube-controller-manager の公式リファレンス](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-controller-manager/): `--allocate-node-cidrs`、`--cluster-cidr` 等の意味。
- [kubeadm implementation details](https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details/): Pod network CIDR 指定時の controller-manager flag、static Pod manifest、`kubeadm-config` ConfigMap。
- [Node API](https://kubernetes.io/docs/reference/kubernetes-api/core-resources/node-v1/): `spec.podCIDR` / `spec.podCIDRs` と Node conditions。
- [Troubleshooting Clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/): Node、condition、イベントを起点とする公式の切り分け。
- [Network Plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/network-plugins/): CNI と container runtime の役割。
- `input/10-bcm-installer-manual/containerization-manual.pdf`: BCM 11、Revision `47eff3c`、2026-09-21。§4.2.1 p.30 の Pod / Service network と `/var/log/cm-kubernetes-setup.log`、§4.2.2 pp.31–32 の Calico / Flannel。原本は Git 管理外。

## 2026-09-25: 切り分け手順作成の実施記録

### 実施者・目的・実行場所

- 実施者: Codex。ユーザーは障害状態を報告したが、この作業中のコマンド実行結果は未共有。
- 目的: `CIDRNotAvailable` とコントロールプレーン `NotReady` を分離して診断し、変更前に必要な証跡と原因別の復旧判断を示す。
- 実行場所: `/root/k8s` の文書リポジトリ。実クラスタ、BCM ヘッドノード、コントロールプレーンには接続していない。
- バージョン: Git 2.43.0。Kubernetes、kubectl、BCM 稼働パッケージ、CNI の版は未確認。

### 実行順と結果

1. `pwd`、`rg --files`、`git status --short --untracked-files=all` でリポジトリと開始時の変更を確認した。開始時の Git 管理対象に変更はなかった。
2. README、要件、環境構成、検証状況、BCM / Kubernetes バージョン、BCM 導入、製品資料、PXE、保守手順を `sed` / `rg` で確認した。本環境では Pod / Service CIDR と基本 CNI が未確定の記録で、実クラスタの構築結果はまだ文書化されていなかった。
3. Git 管理外の `input/` 一覧を確認した。今回の障害ログはなく、既存の BCM 11 Containerization Manual が一次資料として存在することを確認した。内容やファイルは Git へ追加していない。
4. Kubernetes 公式ドキュメントと公式ソースを Web で確認し、`CIDRNotAvailable` の発生箇所、Node の Pod CIDR、controller-manager / kubeadm / CNI の役割を照合した。参照先は上記の根拠資料に記載した。
5. ローカル PDF から関連箇所を再抽出するため `pdfinfo` と `pdftotext` を実行したが、両コマンドがなく終了した。次に Python の `pypdf` で読み取ろうとしたが、module がなく終了した。既に [製品資料](references.md#kubernetes構築の根拠) に版・章・ページと確認結果が記録済みであるため、新たな package 導入は行わず、その記録と原本の存在確認を根拠にした。
6. 本書、README の索引、検証状況を更新した。実クラスタ用コマンドはすべて未実行の診断手順であり、Node / CNI / manifest / サービスへの変更は行っていない。
7. `git diff --check`、見出し・コードブロック・リンクの一覧とリンク先ファイル / 見出しを確認した。最初の `git add` は作業環境の `.git/index.lock` を作成できず失敗し、Git 管理領域への書き込み権限を伴う再試行で 3 文書をステージした。
8. `git diff --cached --name-status`、`git diff --cached --check`、ステージ済み全文、秘密情報候補の検索、ステージ内容と作業ツリーの一致を確認した。`git ls-files -- input` は空で、`git check-ignore` により参照した PDF がルートの `/input/` 規則で除外されることも確認した。追加した URL は Kubernetes の公式資料・公式ソースだけで、認証情報、個人・組織情報、公開可否未確認の接続情報、第三者資料の転載はなかった。既存の公開確認済み検証用ネットワーク 2 件は重複確認対象として引用し、追加の削除・匿名化は不要と判断した。

### 期待結果・実際の結果・残課題

期待結果は、状態採取から Node CIDR 容量、設定差、CNI、kubelet / API 到達性までを安全な順序で切り分け、証拠に応じて復旧方法を選べること。本書に読み取り専用の採取順、判定表、安全条件、復旧後の確認条件を整理した。

実際の障害原因、対象 Node、発生日時、Kubernetes / CNI 版、CIDR、復旧成否は未確認。証跡は利用者報告、本作業のツール出力、Git 差分、上記の公式資料。公開情報チェックの未解決事項はない。次の作業は「まず共有する最小限の証跡」を実クラスタで採取し、結果を本書と [検証状況](validation.md) に追記することである。

## 2026-09-25: kubelet の状態更新停止に関する追加報告と手順整備

- ユーザー報告: Node が NotReady で、Conditions に `kubelet stopped posting node status` と表示。対象名・環境、観測時刻、表示に至るコマンド・画面操作、Ready の Status / Reason、ログ、実行バージョンは未共有。先の etcd 復旧や CIDR 障害との関連は未確認。
- Codex の実施場所・前提: 文書リポジトリのルート。ローカル文書編集と Git コミット権限を使用。Git 2.43.0、Python 3.12.3。実クラスタには接続していない。
- 実行順: `pwd` / `rg --files` / `git status --short --untracked-files=all` → README・AGENTS と環境・既存切り分け・検証状況・保守・版関連文書を `cat` / `rg` / `sed` / `tail` で確認 → Kubernetes 公式資料を Web 検索・閲覧 → Python で本書と検証状況を更新。長い出力は一部省略されたため、関連節を個別に再取得した。開始時の変更はなく、環境文書のパスワード欄は既にプレースホルダーだった。
- 根拠: 今回のユーザーチャット、Codex ツール出力、[Node Status](https://kubernetes.io/docs/reference/node/node-status/) と [Troubleshooting Clusters](https://kubernetes.io/docs/tasks/debug/debug-cluster/)（2026-09-25 閲覧、現行版。本環境の Kubernetes 版は未確認）。既存環境記録は再検証していない。
- 保存手順: `git diff --check`、Markdown のコードブロック・相対リンク確認後、対象 2 文書を `git add`。`git diff --cached --name-status` / `--check` / 差分全文と関連文脈、秘密情報候補、`git ls-files -- input`、`git check-ignore -v -- input/publication-check.txt` を確認してコミットする。コミット名義は公開用の `Repository Maintainer <maintainer@example.invalid>` を使用。コミット後は `git status --short` と ID を確認する。
- 期待結果: 診断と条件付き起動・復旧確認の手順を、実行済み調査と分けて保存する。実際の成果は 4.3 の手順追加と検証状況への報告反映。実環境用コマンドはすべて未実行で、復旧成否は未確認。
- 公開確認範囲: 今回のステージ済み 2 文書の差分と文脈、ファイル名・コミット情報・input 非追跡と除外。実値は追加せず、ノード名・接続先は置換用表記。原本転載なし。公開・push と過去履歴全体の監査は対象外。確認結果と残変更は完了報告に記載する。
