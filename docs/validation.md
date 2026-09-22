# 検証状況

最終整理日: 2026-09-23

初期資料 `docs/vm-list.md` の準備・検証状況、`input/` に保存された証跡、および 2026-09-22 の利用者提供ネットワーク構成をもとに整理しています。同日夜には BCM ヘッドノード上で読み取り専用の実機調査を行いました。証跡は `input/40-bcm-pxe/2026-09-22-headnode-check.txt`。その後、利用者がライセンスを登録し、23:26 JST に登録後の状態を確認しました（証跡: `input/50-bcm-license/2026-09-22-post-registration-check.txt`）。9 月 23 日には利用者提供の PXE 画像 4 枚を確認し、ヘッド上で node001 の UP と同期完了を再照会しました。最初の IP 指定 SSH は未登録ホスト鍵の検証で停止しましたが、00:17 JST にホスト名 `node001` で接続し、ノード内コマンドと外部 HTTPS を確認しました。エージェントによる設定変更・VM 起動・PXE 再展開は行っていません。[初回展開記録](bcm-pxe-provisioning.md#2026-09-23-node001-の初回-pxeos-展開記録) を参照。

「確認済み（初期記録）」は既存の記載を引き継いだものです。「作成済み（利用者提供情報）」は利用者から完了と報告された構成で、今回実環境で確認したものではありません。「画面確認」は保存された画面で確認できる範囲、「未実施」は初期資料で今後の作業とされた項目、「未確認」は完了を示す証跡がまだ整理できていない項目です。「実機確認」は今回のヘッドノード上の照会・疎通で確認した範囲です。「提供ログ確認」は利用者が各実行場所で実行した出力を読んだ結果であり、エージェントの直接実行とは区別します。

9 月 23 日の後続共有では、cp2 の起動前 libvirt 構成と、BCM 上の node002 の MAC 登録・`INSTALLING` 表示に続き、`UP` への移行を提供ログで確認しました。さらに SSH・OS 内部・外部 HTTPS を提供ログで確認しました。同期ログ自体は未共有です。[起動後の確認記録](bcm-pxe-provisioning.md#2026-09-23-node002-の-ssh-と-os-内部の確認) を参照。ユーザーの実行日時・終了コードは未記録で、今回の Codex 作業はログの確認と文書更新のみです。

続く提供ログで cp3 の内部 NIC・MAC 登録と node003 の UP も確認しました。node003 の同期ログ・SSH・OS 内部・外部通信は未確認です。[実施記録](bcm-pxe-provisioning.md#2026-09-23-node003-の-nicmac-登録と-up-確認) を参照。

## 現在の状況

| 項目 | 状態 | 根拠・確認範囲 |
|---|---|---|
| 7 台の VM 作成と UEFI 起動 | 確認済み（初期記録） | 初期 `docs/vm-list.md` の記載。割り当ては [VM 一覧](vm-list.md) を参照 |
| 3 つの仮想ネットワークと 11 本の NIC 接続 | 作成済み（利用者提供情報） | 2026-09-22 提供。`input/20-network/2026-09-22-network-notes.md` に保存。[環境構成](environment.md#ネットワーク) に整理。libvirt 側 NAT・DHCP/DNS 不提供、ワーカー追加 NIC の PXE ROM 無効も提供情報に基づく |
| BCM / cp1 の libvirt 接続と内部ネットワーク | 提供ログ確認 | BCM の内部・外部 MAC と接続先がヘッド実測に一致。cp1 も同じ内部ネットワークの定義。内部ネットワークは DHCP 定義なし・DNS 無効。[確認範囲と証跡](environment.md#仮想化ホスト側の接続確認) |
| cp1 の電源・OS ディスク | 起動後画面・UP 確認 | 展開前は停止中・vda 1 台 128 GiB。9 月 23 日は起動後画面で virtio 128G を認識。SSH で実パーティションと `/dev/vda3` の XFS ルートを確認。UEFI・Secure Boot の設定値は未確認。[起動後確認](environment.md#2026-09-23-node001-の起動後確認) |
| cp2 の構成・起動後状態 | 提供ログ確認・UP / SSH / 外部 HTTPS | 起動前の libvirt 定義に加え、UP、SSH、予定 IP、XFS ルート、実パーティション、有効な swap、失敗サービス 0 件、DNS と HTTP 200 を確認。同期ログと再起動後は未確認。[起動後構成](environment.md#2026-09-23-node002-の起動後確認) |
| cp3 の NIC・MAC 登録・BCM 状態 | 提供ログ確認・UP 表示 | 内部 NIC の計画 MAC・ネットワークへの接続定義と、BCM の登録 MAC・予定 IP・UP を確認。停止状態・ディスク・UEFI 設定・同期ログ・SSH・OS 内部は未確認。[構成確認](environment.md#2026-09-23-cp3-の-nic-と-bcm-登録確認) |
| PXE 対象 6 台の DHCP 要求送信 | 確認済み（初期記録） | 初期 `docs/vm-list.md` の記載。BCM からの応答・OS 展開成功までは示していない |
| ワーカーの追加 NIC・ディスク | 確認済み（初期記録） | QEMU での認識を確認したとの記載。ゲスト OS 内での利用確認とは区別する |
| BCM インストールメディアの整合性チェック | 画面確認 | [BCM インストール記録](bcm-installation.md) の S05 に成功表示あり |
| BCM インストーラーでの設定 | 画面確認 | 30 枚を [BCM インストール手順と設定記録](bcm-installation.md) に整理。S22 の Summary と S23～S30 の Show config まで確認 |
| BCM のインストール完了・再起動後の稼働 | 実機確認 | 利用者の導入完了報告に加え、Ubuntu と CMDaemon の稼働を確認。DHCP・DNS・HTTP・NFS・SSH・NTP は active。OS / パッケージ版は [環境構成](environment.md#2026-09-22-の稼働後確認)。インストーラーの完了ログ自体は未取得 |
| Base View の接続 | ヘッドから HTML 配信確認・ブラウザー未確認 | 9 月 23 日に cmd active、TCP 8081 待受を確認。通常の curl は証明書チェーンの検証で失敗（終了 60）。認証情報なしの単発 `-k` GET は HTTP 200、title は Base View。既存のポート転送・ブラウザー Proxy はユーザー報告で整備済み。Proxy 経由の画面表示・ログインは未確認。[接続手順・証跡](bcm-base-view.md) |
| SSH 公開鍵・Codex CLI | 設置を実機確認・node002 接続を提供ログ確認 | authorized_keys の存在・非空・権限と CLI 0.155.1 を確認。node001 は公開鍵認証で成功。node002 も root ログイン成功、ED25519 ホスト鍵の新規保存表示あり。node002 の認証方式・指紋の別経路照合は未記録。残り 4 台は未検証 |
| OS 全体のサービス状態 | 失敗ユニットあり | 22 時台は shorewall6 の 1 件（IPv6 interfaces 未定義、IPv4 shorewall は active）。23:26 の確認では fwupd-refresh も失敗し、計 2 件。fwupd-refresh の原因とライセンス登録との関連は未調査。CMDaemon は active |
| BCM のライセンス条件 | 登録完了・実機確認 | Free / Advanced、Licensed nodes は使用 1／上限 10。ヘッドを含む 7 台の要件を満たす。`verify-license verify` は終了コード 0、確認時点で有効期間内。正確な有効期間は Git 管理外の証跡に保持し、公開文書では省略する。登録前の Temporary / 上限 2 から更新。[登録手順と証跡](bcm-licensing.md) |
| ライセンス登録後の証明書 | ヘッド・配信元を実機確認 | cmd は active、ヘッド UP。default-image と node-installer の cluster.pem がヘッドと一致。計算ノードでの新証明書取得は PXE 展開時に確認する |
| ゲストの IP・ゲートウェイ・DNS 設定 | ヘッド・cp1 実機確認、cp2 提供ログ確認 | node002 の内部 MAC 登録に加え、ゲストの予定 IP・ヘッド経由の経路・外部名前解決も確認。ヘッドと cp1 の結果は既存記録を引き継ぐ。node003 も登録 MAC・予定 IP を BCM 一覧で確認したが、ゲスト内部は未確認。ワーカー 3 台は MAC 未登録で、定義の IP は予約値と不一致。[構成](environment.md) |
| BCM による内部ネットワークの DHCP・PXE 提供 | node001 の PXE・同期完了・起動確認 | PXE メニュー、node-installer での識別と FULL 展開、予定 IP、起動後画面を確認。ヘッド上で rsync 完了と UP を再照会。DHCP パケット自体は未採取。[実施記録](bcm-pxe-provisioning.md#2026-09-23-node001-の初回-pxeos-展開記録) |
| ヘッド・計算ノードのディスクレイアウト | ヘッド・cp1 実機確認、cp2 提供ログ確認 | cp1 / cp2 とも vda 128 GiB、EFI / swap / XFS ルートを確認。swap 16 GiB は両台とも有効。default カテゴリの設定と BCM の swap 無効化実装は前回確認を引き継ぐ。Kubernetes 構築時の実動作、他 4 台のゲスト内部、ワーカーの OS 用ディスク識別は未確認。[展開手順](bcm-pxe-provisioning.md) |
| CUDA 追加パッケージ | 選択画面確認 | S21・S22 で選択あり。GPU なし構成での選択理由と導入結果は未確認 |
| 内部ネットワークから外部へのルーティング・NAT | ヘッド設定・cp1 / cp2 の外部疎通を確認 | ヘッドの forwarding / MASQUERADE と cp1 の既存結果に加え、cp2 のヘッド経由デフォルト経路・外部名前解決・IPv4 HTTPS HTTP 200 を提供ログで確認。他の 4 台は未確認 |
| R-01: BCM による 6 台への OS 展開 | 3 / 6 台で UP、うち 2 台は OS 内部・外部 HTTPS も確認 | node001 / node002 は UP・SSH・ディスク上のルート・失敗サービスなし・外部 HTTPS を確認済み。node003 は UP 表示確認までで、OS 内部は未確認。node002 / node003 の同期ログ・実際の展開モードの証跡は未共有。ワーカー 3 台は MAC 未登録・DOWN / unassigned。[node003 の実施記録](bcm-pxe-provisioning.md#2026-09-23-node003-の-nicmac-登録と-up-確認) |
| R-02: Kubernetes クラスタ構築・基本動作 | 未確認 | コントロールプレーン 3 台・ワーカー 3 台が目標。構築後・再起動後の swap 無効を確認する。[BCM 実装調査と選択肢](bcm-pxe-provisioning.md#kubernetes-と-swap) |
| R-03: Multus 導入・動作 | 未実施 | 初期資料で今後実施と記載 |
| ワーカーの LVM 初期化 | 未実施 | 初期資料で今後実施と記載 |
| R-04: TopoLVM 導入・動的割り当て | 未実施 | 初期資料で今後実施と記載 |

要件 ID と確認条件は [検証要件](requirements.md) を参照してください。

## 次の作業

1. node003 は登録・UP 確認済み。[手順 6.3](bcm-pxe-provisioning.md#63-cp2-の起動後を確認して-cp3-へ進む) の対象を node003 に置き換え、同期ログ・SSH・OS 内部・外部通信を確認する。node002 の同期ログも証跡を補完する。cp3 の起動前ディスク・UEFI 設定とヘッドの永続 NIC 構成は出力未共有のため、必要な記録を別途補完する。
2. cp3 に続いてワーカー 3 台を [展開手順](bcm-pxe-provisioning.md#64-ワーカーの追加ディスクを保護して展開する) に従って準備する。OS 用と TopoLVM 用ディスクを識別し、停止中の MAC 登録とワーカー IP 調整後、各台の展開・起動・外部通信を確認する。shorewall6 と fwupd-refresh の失敗原因・対応は引き続き別途確認する。
3. Kubernetes のコントロールプレーン・etcd の配置と、[ネットワークのアドレス設計](requirements.md#構築前に確認する事項) を確定して構築し、各ノードの役割・Ready 状態と基本動作を確認する。
4. Multus の追加ネットワークと、追加ディスクを利用した LVM / TopoLVM を構築し、要件ごとの確認結果を記録する。

ヘッドの実パーティション構成は記録済み。CUDA の選択意図・導入結果は引き続き未確認。詳細な未確認事項は [BCM インストール記録](bcm-installation.md#残る確認事項) を参照する。

## 結果の追記方法

詳細な操作や出力は対象の構築・検証文書に記録し、本書には状態と根拠へのリンクを追記します。失敗や未解決事項も、発生条件と次の確認内容を残してください。資料の追加だけで完了に変更せず、[検証要件](requirements.md) の確認条件を満たしたかを判断します。
