# 検証状況

最終整理日: 2026-10-15

初期資料 `docs/vm-list.md` の準備・検証状況、`input/` に保存された証跡、および 2026-09-22 の利用者提供ネットワーク構成をもとに整理しています。同日夜には BCM ヘッドノード上で読み取り専用の実機調査を行いました。証跡は `input/40-bcm-pxe/2026-09-22-headnode-check.txt`。その後、利用者がライセンスを登録し、23:26 JST に登録後の状態を確認しました（証跡: `input/50-bcm-license/2026-09-22-post-registration-check.txt`）。9 月 23 日には利用者提供の PXE 画像 4 枚を確認し、ヘッド上で node001 の UP と同期完了を再照会しました。最初の IP 指定 SSH は未登録ホスト鍵の検証で停止しましたが、00:17 JST にホスト名 `node001` で接続し、ノード内コマンドと外部 HTTPS を確認しました。エージェントによる設定変更・VM 起動・PXE 再展開は行っていません。[初回展開記録](bcm-pxe-provisioning.md#2026-09-23-node001-の初回-pxeos-展開記録) を参照。

「確認済み（初期記録）」は既存の記載を引き継いだものです。「作成済み（利用者提供情報）」は利用者から完了と報告された構成で、今回実環境で確認したものではありません。「画面確認」は保存された画面で確認できる範囲、「未実施」は初期資料で今後の作業とされた項目、「未確認」は完了を示す証跡がまだ整理できていない項目です。「実機確認」は今回のヘッドノード上の照会・疎通で確認した範囲です。「提供ログ確認」は利用者が各実行場所で実行した出力を読んだ結果であり、エージェントの直接実行とは区別します。

9 月 23 日の後続共有では、cp2 の起動前 libvirt 構成と、BCM 上の node002 の MAC 登録・`INSTALLING` 表示に続き、`UP` への移行を提供ログで確認しました。さらに SSH・OS 内部・外部 HTTPS を提供ログで確認しました。この時点では同期ログ自体は未共有でした。[起動後の確認記録](bcm-pxe-provisioning.md#2026-09-23-node002-の-ssh-と-os-内部の確認) を参照。ユーザーの実行日時・終了コードは未記録で、当該記録の Codex 作業はログの確認と文書更新のみです。

続く提供ログで cp3 の内部 NIC・MAC 登録と node003 の UP も確認しました。この時点では node003 の同期ログ・SSH・OS 内部・外部通信は未確認でした。[実施記録](bcm-pxe-provisioning.md#2026-09-23-node003-の-nicmac-登録と-up-確認) を参照。

01:21～01:25 JST に Codex が BCM ヘッドから 3 台を直接確認し、いずれも FULL 同期完了・UP・SSH 公開鍵認証・OS 内部・外部 HTTPS 成功を確認しました。node003 の初回 SSH は未登録ホスト鍵で停止し、展開元イメージの公開鍵との照合後に成功しました。[一括確認の実施記録](bcm-pxe-provisioning.md#2026-09-23-node001003-の-bcm-からの一括確認) を参照。

2026-09-25 に利用者から、Kubernetes コントロールプレーンが `CIDRNotAvalible` と表示され `NotReady` であるとの報告があった。チャット上の綴りは正式なイベント理由 `CIDRNotAvailable` を指すものとして切り分ける。元のイベント、Node condition、Kubernetes / CNI 版、Pod / Service CIDR、controller-manager ログは未共有で、Codex は実クラスタを照会していない。イベント理由の実表記、`CIDRNotAvailable` と `NotReady` の因果関係および原因は未確認である。変更前の採取項目と判定方法を [CIDRNotAvailable / NotReady 切り分け](kubernetes-cidr-troubleshooting.md) に整理した。

2026-09-25 の追加報告で、NotReady の Conditions に `kubelet stopped posting node status` とあることが分かった（ユーザー報告、原出力未共有）。対象環境と先の CIDR 障害・etcd 復旧との関連は未確認。[状態更新停止の確認と条件付き復旧手順](kubernetes-cidr-troubleshooting.md#43-kubelet-stopped-posting-node-status-の確認と条件付き復旧) に従い、対象ノードの kubelet ログと API 到達性を優先して確認する。Codex による実環境操作・復旧確認は未実施。

続いて状態更新エラーと `connection refused` の表示が報告された。宛先・原ログ・実行操作は未共有。[接続拒否の切り分け](kubernetes-cidr-troubleshooting.md#44-error-updating-node-status-will-retry-と-connection-refused) で API / LB の待受と API コンテナのログを確認する段階。原因・復旧は未確認。

さらにユーザーが crictl で API ログを確認し、etcd クライアント証明書ファイルの `no such file or directory` を報告した。証明書の参照・配置を起動阻害要因として調査中。[BCM の条件付き修復手順](etcd-backup-restore.md#etcd-クライアント証明書が見つからない場合の復旧) を整理した。追加回答では障害環境は BCM 11.33、CP 3 台中 1 台が稼働し kubectl 利用可能（ユーザー報告）。正常 CP を維持し、障害 CP を順次修復する方針。ホスト側の欠落 / mount 不整合、実パッケージ版、復旧結果は未確認。

続いて etcd status には正常ノード 1 台だけだったとの報告があった。照会元ログ・メンバー一覧・health のどれを指すかは未確認。[1 台表示の判定](etcd-backup-restore.md#2026-09-25-etcd-status-が-1-台だけに見える場合) に従って原出力を確認する。単一メンバー構成・quorum 喪失のいずれも現時点では断定しない。

最新の追加報告で、元は etcd 3 台構成、バックアップ・リストア試験で 1 台を復元済み、直前に案内した kubectl の健全性確認は全項目 OK・check passed と報告された（正確なコマンド・原出力未共有）。単一ノード復元後の API 健全性成功として記録し、旧 3 台中 1 台だけ稼働する quorum 不足と断定しない。[3 台構成への復帰手順](etcd-backup-restore.md#2026-09-25-1-台復元後の正常応答と-3-台構成への復帰) を整理した。残り 2 台の追加、API 証明書修復、全 Node Ready、復元データの一致は未確認で、R-05 全体の合格には変更しない。

追加復帰対象 CP で API コンテナが crictl に表示されなくなったとのユーザー報告があった。停止済みを含めた一覧・CRI endpoint・manifest・kubelet の状態、直前の操作は未共有。[API コンテナ不表示の切り分け](kubernetes-cidr-troubleshooting.md#2026-09-25-対象-cp-の-api-コンテナが-crictl-に表示されない) を追加し、再作成側のログ確認を優先する。追加回答で `update_apiserver` と再起動を実施したとの報告を受けた。引数・順序・再起動対象・終了結果は未共有で、API の再作成失敗を優先確認する。etcd 再追加の実行と API 修復成否は未確認。

最新報告では、先に API コンテナを調査した CP は正常復旧した（ユーザー報告、最終操作・原出力未共有）。続いて別 CP の `/var/lib/kubelet/` が空で、kubelet 起動時に `config.yaml` の生成待ちとなるとの報告を受けた。対象ノード用設定の再生成とクライアント認証情報の確認を [条件付き修復手順](kubernetes-cidr-troubleshooting.md#2026-09-25-別-cp-の-kubelet-が-configyaml-の生成待ちになる) に整理した。Codex による現地操作は未実施で、新対象の復旧・全 CP Ready・etcd 3 メンバーの正常化は未確認。

## 2026-10-14 の各ノード実機確認

00:48～00:49 JST、Codex が BCM と SSH で再照会した同日最初の観測。後続の変更・確認は [導入前準備](#2026-10-14-の導入前準備) を優先する。詳細は [実行手順・証跡](node-status.md)。

| 対象（VM / BCM 名） | BCM 状態 | SSH・OS 確認 | 注意点 |
|---|---|---|---|
| tk8s-bcm / ヘッド | UP | ローカル照会、cmd active | shorewall6.service が failed |
| tk8s-cp1 / node001 | UP | SSH 成功、失敗ユニット 0 | kubelet / containerd 標準 unit なし |
| tk8s-cp2 / node002 | UP | SSH 成功、失敗ユニット 0 | 同上 |
| tk8s-cp3 / node003 | UP | イメージ公開鍵照合後 SSH 成功、失敗ユニット 0 | 同上 |
| tk8s-worker1 / node004 | UP | イメージ公開鍵照合後 SSH 成功、失敗ユニット 0 | 同上 |
| tk8s-worker2 / node005 | DOWN / unassigned | SSH は No route to host | BCM で MAC 未登録、VM 電源未確認 |
| tk8s-worker3 / node006 | DOWN / unassigned | SSH は No route to host | 同上 |

Kubernetes の Ready / API / etcd は今回未確認。9 月 25 日にユーザーが報告した障害環境との同一性は未確認であり、その復旧成否を今回の結果から判定しない。構成の観測値は [環境構成](environment.md#2026-10-14-の状態確認) に記載。要件全体の合格状況は変更しない。

## 2026-10-14 の導入前準備

ユーザーの訂正指示により Kubernetes インストール手前までを対象とした。[実施記録](kubernetes-preparation.md) と [構成の正本](environment.md#2026-10-14-の導入前準備) を参照。

- node001～004 は OS・予定 IP / 経路・時刻同期・cmd・失敗サービスなしを確認。DNS の初回失敗は再試行で解消し、直接 IPv4 HTTPS 成功。
- node004 は OS-only の disksetup へ切替済み。通常 AUTO の PXE / SYNC 再起動後に LVM 識別子と試験データ保持を確認。検証用 LV を削除し seed のみへ復帰した。
- node005・006 は後続の [提供報告と BCM 登録](kubernetes-preparation.md#6-worker23-の提供報告を照合して-bcm-に登録する) により用途・target・容量を照合し、IP / MAC / 初回レイアウト保存まで完了。DOWN・未展開で、初回起動とディスク内容確認が必要。BCM ヘッドから物理ホストへの直接 SSH は信頼済みホスト鍵・利用可能な agent がなく利用できない。別チャットへの送信機能もこのセッションにはなく、情報照会と電源操作に限定した依頼文を利用者へ提示した。
- OS-only FULL 保持試験と広範なバックアップは自動承認レビューが拒否。その後ユーザーが通常再起動までと指定したため、両方未実行のまま今回の範囲から外した。
- BCM のライセンス上限は予定台数を満たし、cm-kubernetes-setup のヘルプ・導入候補一覧まで確認した。swap / runtime / kubelet / CNI / etcd の構築工程は未実行。

**6 台全体の導入前準備は未完了。** 残るワーカー 2 台の起動・ディスク内容確認・OS / LVM 展開・運用用切替・通常再起動での保持確認が必要。ヘッドの shorewall6 は既存の failed のままで、IPv4 通信を妨げる事象は今回観測していない。

### 後続更新: node005 の展開完了

01:38 JST に node005 の初回 FULL、通常 OS 起動、運用用切替、AUTO → SYNC 再起動後の LVM / 試験データ保持を確認した。試験 LV は削除済み。node001～005 UP、node006 DOWN。6 台全体の導入前準備はまだ未完了で、残りは node006。上の 4 台時点の記録は実施順を示す。[最新手順](kubernetes-preparation.md#7-node005-の初回展開と通常再起動試験)・[構成](environment.md#2026-10-14-node005-の初回展開と通常再起動)。

### 最終更新: node006 と今回の準備範囲の完了

01:51 JST、node006 も初回展開・OS / 通信確認・OS-only 切替・通常再起動での保持試験を完了。試験 LV は削除済み、ヘッド + 6 ノード UP、ライセンス検証成功（7 / 10）、3 ワーカー全台の運用設定を再照合した。**今回依頼された OS・ストレージ準備は完了。** Kubernetes は未導入で、版・CIDR・CNI・API endpoint の決定とセットアップは後続工程。[最終記録](kubernetes-preparation.md#8-node006-の初回展開と通常再起動試験)・[最終構成](environment.md#2026-10-14-node006-完了と導入前の最終状態)。上記の未完了表示は各時点の履歴。

## 現在の状況

| 項目 | 状態 | 根拠・確認範囲 |
|---|---|---|
| 7 台の VM 作成と UEFI 起動 | 確認済み（初期記録） | 初期 `docs/vm-list.md` の記載。割り当ては [VM 一覧](vm-list.md) を参照 |
| 3 つの仮想ネットワークと 11 本の NIC 接続 | 作成済み（利用者提供情報） | 2026-09-22 提供。`input/20-network/2026-09-22-network-notes.md` に保存。[環境構成](environment.md#ネットワーク) に整理。libvirt 側 NAT・DHCP/DNS 不提供、ワーカー追加 NIC の PXE ROM 無効も提供情報に基づく |
| BCM / cp1 の libvirt 接続と内部ネットワーク | 提供ログ確認 | BCM の内部・外部 MAC と接続先がヘッド実測に一致。cp1 も同じ内部ネットワークの定義。内部ネットワークは DHCP 定義なし・DNS 無効。[確認範囲と証跡](environment.md#仮想化ホスト側の接続確認) |
| cp1 の電源・OS ディスク | 実機確認・UP / UEFI / XFS | vda 128 GiB・ディスク上のルートと UEFI 起動を確認。libvirt 永続定義・実効 Secure Boot・再起動後は未確認。[最新構成](environment.md#2026-09-23-node001003-の直接確認) |
| cp2 の構成・起動後状態 | 実機確認・FULL 完了 / UP / SSH | 提供ログに続き、Codex が同期ログ・公開鍵認証・fstab・OS 内部・通信を直接確認。再起動後は未確認。[最新構成](environment.md#2026-09-23-node001003-の直接確認) |
| cp3 の NIC・起動後状態 | 実機確認・FULL 完了 / UP / SSH | 提供ログに続き、Codex がゲスト IP・ディスク・UEFI 起動・OS 内部・通信を直接確認。libvirt の起動前構成・永続定義は未確認。[最新構成](environment.md#2026-09-23-node001003-の直接確認) |
| PXE 対象 6 台の DHCP 要求送信 | 確認済み（初期記録） | 初期 `docs/vm-list.md` の記載。BCM からの応答・OS 展開成功までは示していない |
| ワーカーの追加 NIC・ディスク | worker1 の永続定義・仮想容量を提供ログ確認 | 停止中、OS vda / TopoLVM vdb、内部 NIC 優先・Multus ROM 無効、UEFI / Secure Boot 無効の定義を確認。後続の domblkinfo で両ディスク 256 GiB を確認。内容・ゲスト内認識は未確認。worker2・3 は初期記録を引き継ぐ。[構成](environment.md#2026-09-23-worker1-の起動前構成確認) |
| BCM インストールメディアの整合性チェック | 画面確認 | [BCM インストール記録](bcm-installation.md) の S05 に成功表示あり |
| BCM インストーラーでの設定 | 画面確認 | 30 枚を [BCM インストール手順と設定記録](bcm-installation.md) に整理。S22 の Summary と S23～S30 の Show config まで確認 |
| BCM のインストール完了・再起動後の稼働 | 実機確認 | 利用者の導入完了報告に加え、Ubuntu と CMDaemon の稼働を確認。DHCP・DNS・HTTP・NFS・SSH・NTP は active。OS / パッケージ版は [環境構成](environment.md#2026-09-22-の稼働後確認)。インストーラーの完了ログ自体は未取得 |
| Base View の接続 | ユーザー報告・ログイン後の管理画面を確認 | 初回に cmd active・8081 待受・単発 `-k` GET の HTTP 200 を確認。後続の 6 枚で概要・イメージ・File System Parts・ノード一覧・Kubernetes 管理画面の閲覧を確認。NodesTotal 7 / Up 4 / Down 3 は、ヘッドと node001～003 が Up、ワーカー 3 台が Down の一覧と整合。認証入力・Proxy 設定内容・証明書対処操作は未記録。[画面証跡](bcm-base-view.md#2026-09-23-ブラウザー接続と管理画面の確認) |
| SSH 公開鍵・Codex CLI | ヘッドの鍵設置・node001～003 の公開鍵認証を確認 | 3 台とも root で成功。node003 はイメージ公開鍵を一時 known_hosts に固定して検証。3 台の ED25519 ホスト鍵は共有で、固有鍵による識別は未確立。CLI 0.155.1 の確認は以前の記録を引き継ぐ。ワーカーは未検証 |
| OS 全体のサービス状態 | 失敗ユニットあり・解消未確認 | 22 時台は shorewall6 の 1 件（IPv6 interfaces 未定義、IPv4 shorewall は active）。23:26 は fwupd-refresh も失敗し、計 2 件。原因・登録との関連は未調査。後続の Base View は Health Checks `17/17` Pass を表示するが、OS 全体の失敗ユニット解消の証跡とはしない。[画面の確認範囲](bcm-base-view.md#確認結果と限界) |
| BCM のライセンス条件 | 登録完了・実機確認後、GUI で使用数確認 | 登録後の確認は Free / Advanced、Licensed nodes 使用 1／上限 10、`verify-license verify` 終了 0、有効期間内。後続の Base View B02 は Nodes `4 / 10`、Accelerators `0 / 10` を表示。ヘッドを含む 7 台の要件に対するノード上限は維持。登録時の検証結果と GUI の表示時点を区別する。[登録手順](bcm-licensing.md)・[画面証跡](bcm-base-view.md#2026-09-23-ブラウザー接続と管理画面の確認)。正確な有効期間は Git 管理外の証跡に保持 |
| ライセンス登録後の証明書 | ヘッド・配信元を実機確認 | cmd は active、ヘッド UP。default-image と node-installer の cluster.pem がヘッドと一致。計算ノードでの新証明書取得は PXE 展開時に確認する |
| ゲストの IP・ゲートウェイ・DNS 設定 | ヘッド・全 6 ノードを実機確認 | node004 の予定 IP、ヘッド経由の経路・DNS と外部通信も確認。node005・006 の IP・経路・DNS も確認済み。[node004](environment.md#2026-09-23-node004-の初回展開後確認) |
| BCM による内部ネットワークの DHCP・PXE 提供 | node001～006 の FULL 同期・起動を確認 | node004 の同期ログでも FULL と Rsync completed を確認。DHCP パケット自体は未採取。node001～003 は以前の結果を引き継ぐ。[node004](worker-storage.md#2026-09-23-node004-の初回展開後確認) |
| ヘッド・計算ノードのディスクレイアウト | ヘッド・全 6 ノードを実機確認 | node004 は vda 256 GiB の EFI / swap / XFS ルートと、vdb の PV / VG / 4 MiB seed を確認。swap 16 GiB 有効。ヘッド・cp1～3 は以前の結果を引き継ぐ。Kubernetes 構築後と再起動後は未確認。[node004](environment.md#2026-09-23-node004-の初回展開後確認) |
| CUDA 追加パッケージ | 選択画面確認 | S21・S22 で選択あり。GPU なし構成での選択理由と導入結果は未確認 |
| 内部ネットワークから外部へのルーティング・NAT | ヘッド設定・全 6 ノードの外部疎通を確認 | node004 でもヘッド経由の経路、外部 DNS、docs.nvidia.com への IPv4 HTTPS HTTP 200 を確認。ヘッド・cp1～3 は以前の結果を引き継ぐ。node005・006 は 10 月 14 日に同様に確認 |
| R-01: BCM による 6 台への OS 展開 | 6 / 6 台で初回展開・起動後の基本確認完了 | node004 で FULL 同期完了・UP・SSH・OS / LVM・失敗サービス 0・外部 HTTPS を確認。node001～003 は前回の成功結果を引き継ぐ。node005・006 も展開・基本確認完了。[cp1～3](bcm-pxe-provisioning.md#2026-09-23-node001003-の-bcm-からの一括確認)・[node004](worker-storage.md#2026-09-23-node004-の初回展開後確認) |
| R-02: Kubernetes クラスタ構築・基本動作 | 本検証環境は未構築・今回は導入前まで | 10 月 14 日の照会で overlay・標準 kubelet 設定等の不存在を確認。別環境か未確定の 9 月 25 日の障害報告は [切り分け記録](kubernetes-cidr-troubleshooting.md) に保持し、本検証の構築済み証跡としない。導入後・再起動後の swap 無効も未検証 |
| R-03: Multus 導入・動作 | 導入 YAML 作成・実機未実施 | 2026-10-15 に利用者指定の bond3 用 [最小手順・適用 YAML](multus-macvlan-whereabouts.md) を追加。YAML / JSON の静的確認のみ。実クラスタとの互換性・導入・疎通は未検証 |
| ワーカーの LVM 初期化 | node004～006 は運用用切替・AUTO 保持試験合格 | seed 4 MiB のみ、空き容量回復。OS-only FULL は今回省略。PVC 動作は未確認。[最新記録](kubernetes-preparation.md) |
| R-04: TopoLVM 導入・動的割り当て | 未実施 | 初期資料で今後実施と記載 |
| R-05: etcd バックアップ・リストア | 計画作成・未実施 | [専用 namespace による復元判定手順](etcd-backup-restore.md) を作成。現環境は Kubernetes 未構築で、別環境の版・構成・BCM multi-member 復旧順も未確認。snapshot 取得・差分作成・restore は実行していない |

要件 ID と確認条件は [検証要件](requirements.md) を参照してください。

2026-09-25 の追加報告では、etcd 復旧前後に利用者がノードを再起動し、Calico apiserver Pod が Terminating に残っている。対象が本検証クラスタか別環境か、復旧・再起動の実行順と成功は未確認で、R-05 の試験成功には変更しない。[報告記録と対象 Pod の削除手順](etcd-backup-restore.md#復旧前後の再起動と-terminating-pod) を参照。削除・再作成結果の共有待ち。

## 次の作業

1. OS 展開・3 ワーカーの VG 準備と通常再起動保持確認は完了。今回の作業はここで終了し、Kubernetes の導入は後続の構築依頼で行う。
2. libvirt 永続構成・Secure Boot など不足する記録、共有 SSH ホスト鍵の扱いを確認する。ヘッドの shorewall6 は IPv6 用 interfaces の定義なしで失敗しており、IPv6 を利用する場合は管理設定を整備する。今回の失敗ユニット一覧に fwupd-refresh はない。
3. 今回は Kubernetes をインストールしない。次の構築時に導入版・CNI・API 接続先・アドレス範囲を確定し、専用コントロールプレーン 3 台と worker 3 台を選ぶ。別環境か未確定の利用者報告 `CIDRNotAvailable` / `NotReady` については、[読み取り専用の切り分け](kubernetes-cidr-troubleshooting.md) に従い Node condition、イベント、Pod CIDR、controller-manager、CNI、kubelet の証跡を採取する。原因確定前に CIDR や manifest を変更しない。コントロールプレーン・etcd の実配置、Kubernetes / CNI 版、アドレス設計、全 Node の役割・Ready 状態と基本動作を記録する。
4. Kubernetes 構築後、[etcd バックアップ・リストア試験](etcd-backup-restore.md) の対象版と multi-member 復旧順を確定する。廃棄可能な環境と停止時間を確保してから実行し、専用 resource と API / etcd / Node の復元結果を記録する。
5. Multus の追加ネットワークと、追加ディスクを利用した LVM / TopoLVM を構築し、要件ごとの確認結果を記録する。

ヘッドの実パーティション構成は記録済み。CUDA の選択意図・導入結果は引き続き未確認。詳細な未確認事項は [BCM インストール記録](bcm-installation.md#残る確認事項) を参照する。

## 結果の追記方法

詳細な操作や出力は対象の構築・検証文書に記録し、本書には状態と根拠へのリンクを追記します。失敗や未解決事項も、発生条件と次の確認内容を残してください。資料の追加だけで完了に変更せず、[検証要件](requirements.md) の確認条件を満たしたかを判断します。
