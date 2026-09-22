# BCM インストール手順と設定記録

2026-09-22 に保存された 30 枚のスクリーンショットをもとに、BCM ヘッドノードのインストール手順と設定を整理する。**Summary と Deployment 画面上の Show config まで確認できるが、インストールの完了メッセージ・再起動・稼働後の確認結果は写っていない。** 現在の進捗と後続作業は [検証状況](validation.md) に集約する。

本書の画面記録における「確認」は保存画面の読み取りを意味する。入力途中の値、Summary、Show config を区別し、後続画面で確認できる値を記録する。インストーラー実行ログはなく、既定値と利用者が変更した値の区別は、画面間の変化がある箇所に限る。

同日夜、利用者から導入完了の報告があり、ヘッドノード上の読み取り専用調査で OS と CMDaemon 等の稼働を確認した。実測構成は [環境構成の稼働後確認](environment.md#2026-09-22-の稼働後確認)、進捗・残課題は [検証状況](validation.md)、次の操作は [PXE・OS 展開手順](bcm-pxe-provisioning.md) を参照。証跡は `input/40-bcm-pxe/2026-09-22-headnode-check.txt`。インストールの再実行、ネットワーク変更、計算ノードの起動・展開は行っていない。

同日 23 時台には利用者がライセンス登録を実施し、登録後の有効性・ノード上限・証明書配布を実機で確認した。操作の詳細は [ライセンス登録手順と実施記録](bcm-licensing.md) を参照する。

## 対象と前提

| 項目 | 確認内容 | 根拠 |
|---|---|---|
| 実施日・時刻 | 2026-09-22 17:31:25～20:15:43。ファイル名に基づき、撮影時刻のタイムゾーンは未記録 | S01～S30 |
| 対象 VM | noVNC のタブに `QEMU (tk8s-bcm)` と表示 | S01～S30 |
| インストーラー | `Base Command Manager installer`、`v11.34.0 (UBUNTU2404)` | 各画面のヘッダー |
| OS の表示 | `Ubuntu Server 24.04` | S02 |
| NIC | `enp1s0`、`enp2s0`、両方 `virtio_net` | S04 |
| ディスク | `/dev/vda`、`549GB Virtual I/O device` | S04、S19 |
| メディア | `/dev/sr0 (BCM Install Media)`、整合性チェック成功 | S05 |

`v11.34.0` はインストーラーの表示であり、導入後の BCM パッケージのバージョンではない。ディスクの `549GB` も画面表記で、[VM 一覧](vm-list.md) の 512 GiB とは単位が異なる。VM のリソースと仮想化条件は VM 一覧と [環境構成](environment.md) を参照する。ISO の接続・起動方法は今回の画像に含まれない。

公開文書では、公開可否が未確認のゲストホスト名・ドメインを `<HEADNODE_HOSTNAME>`、`<INTERNAL_DOMAIN>`、`<EXTERNAL_DOMAIN>` に匿名化する。これらは実際の入力値ではない。IP・MAC 等の公開確認の範囲は [環境構成のネットワーク](environment.md#ネットワーク) に記載している。パスワードと接続トークンは転記しない。

## 画面に沿った手順

以下は保存画面から組み立てた操作順であり、全クリックの実行ログではない。設定画面で内容を確認して `Next` へ進み、必要に応じて前の画面に戻る流れを示す。撮影順では Networks が BMC configuration より先に写っており、画面の往復があったことに注意する。

| 順序 | 画面 | 操作・確認する内容 | 保存画面で確認できた状態 |
|---:|---|---|---|
| 1 | NVIDIA EULA / Ubuntu ライセンス | 内容を確認し、同意する場合に `I agree` を選択する | 両画面ともチェックあり（S01、S02） |
| 2 | Kernel modules | 認識されたモジュールを確認する | 一覧を表示。追加・削除操作は記録なし（S03） |
| 3 | Hardware info | 対象 VM の NIC・ディスクを確認する | NIC 2 本と `/dev/vda` を検出（S04） |
| 4 | Installation source / DVD/ISO/USB | `/dev/sr0` を選択し、`Run media integrity check` で確認する | 整合性チェックと検証の成功表示あり（S05） |
| 5 | Cluster settings | クラスタ名、時刻、DNS、Environment modules を確認する | 入力欄を確認。DNS 空欄は後述の確認事項（S06） |
| 6 | HPC workload manager | `None` を選択する | `None` 選択（S07、S22） |
| 7 | Network topology | `Type1` を選択する | 内部ネットワークからヘッドノード経由で外部へ接続する構成を選択（S08） |
| 8 | Head node settings | ホスト名、管理者パスワードと確認欄、機種を入力する | パスワード入力あり、機種 `Other`（S09） |
| 9 | Compute nodes settings | ラック数、台数、ノード命名規則、機種を入力する | 1 ラック・6 ノードを入力（S10） |
| 10 | BMC configuration | ヘッドノード・計算ノードの BMC 有無を指定する | 両方 `No`（S13、S22） |
| 11 | Networks | 内部ネットワーク・DHCP 動的範囲と、外部の固定 IP 用ネットワークを設定する | 途中の値から変更され、S14・S16 の値を Show config でも確認（S24、S25） |
| 12 | Head node / Compute nodes interfaces | ヘッドの 2 NIC とネットワークを対応付け、計算ノードの `BOOTIF` と `IP offset` を指定する | 入力を確認。MAC と配線の照合・ノード別 IP の生成結果は未確認（S17、S18） |
| 13 | Disk layout | インストール対象のヘッドノードのディスクを選ぶ | `/dev/vda` 選択（S19、S22） |
| 14 | Disk layout settings | ヘッド・計算ノードのレイアウトを選択する | 両方 `One big partition`（S20） |
| 15 | Additional software | 追加ソフトウェアの選択を確認する | `CUDA` にチェックあり（S21、S22） |
| 16 | Summary | 設定・対象ディスクを確認し、問題がなければ `Start` で導入へ進む | Summary と `Start` ボタンを確認（S22）。ディスクへの影響は後述 |
| 17 | Deployment | 進行・完了・エラーを確認し、完了後の再起動と起動確認を記録する | 背景に Deployment と `Reboot`、前面に Show config（S23～S30）。完了本文・再起動操作は未確認 |

## クラスタ共通設定

| 項目 | 表示値・選択状態 | 根拠 |
|---|---|---|
| クラスタ名 | `BCM 11.0 Cluster` | S06 のラベルは画面外。S30 の `clustername` で確認 |
| Organization name | `NVIDIA`（画面表示。利用者の所属を示すものではない） | S06、S30 |
| Administrator email | 空欄 | S06 |
| 初回起動時の管理者向けメール | チェックなし、`sendadminemailfirstboot: false` | S06、S23 |
| Time zone | `(GMT+09:00) Asia/Tokyo`。Summary は `Asia/Tokyo` | S06、S22 |
| Time servers | `0.pool.ntp.org`、`1.pool.ntp.org`、`2.pool.ntp.org` | S06、S22、S23 |
| Nameservers | 空欄 | S06、S22 |
| Search domains | 空欄、`searchdomains: []` | S06、S23 |
| Environment modules | `Tcl modules`、`tmod` の `selected: true` | S06、S23 |
| HPC workload manager | `None` | S07、S22 |
| Network topology | `Type1` | S08 |

`None` は HPC workload manager を初回起動時に構成しない選択で、Kubernetes の導入状況を示さない。Type1 の選択も、実際のルーティング・NAT の動作確認ではない。

Nameservers と Search domains には、外部 DHCP を使う場合は空欄にする旨の案内がある。一方、後続では外部 DHCP を無効にしており、Summary でも Nameservers は空欄のままである。[環境構成の DNS 計画](environment.md#ゲートウェイdnsdhcp-の計画と画面確認) との差として、導入後の名前解決を確認する。ネットワークごとの Domain name と、ここでの Search domains は別の設定欄である。

## ヘッドノード・計算ノード・BMC

| 対象 | 項目 | 表示値・入力状態 | 根拠 |
|---|---|---|---|
| ヘッド | Hostname | `<HEADNODE_HOSTNAME>`（匿名化済み）。VM 名 `tk8s-bcm` とは異なる | S09、S29 |
| ヘッド | Administrator password / 確認欄 | 両方に入力あり。実値は非掲載 | S09、S29 |
| ヘッド | Hardware manufacturer | `Other` | S09、S22 |
| 計算ノード | Number of racks | `1` | S10、S30 |
| 計算ノード | Number of nodes | `6` | S10、S30 |
| 計算ノード | Node start number | `1` | S10、S30 |
| 計算ノード | Node base name | `node` | S10、S30 |
| 計算ノード | Node digits | `3` | S10、S30 |
| 計算ノード | Hardware manufacturer | `Other` | S10、S22、S30 |
| 両方 | BMC | `No`、Summary は `No BMC` | S13、S22 |

命名規則から `node001`～`node006` が想定されるが、生成後のノード一覧はない。これらは命名規則からの推定であり、登録済みの名前ではない。VM 名・BCM ノード名・MAC・Kubernetes の役割の対応は未確認。

Show config の `bmcTypes` には IPMI 等の候補が表示されるが、その存在を BMC 有効の根拠にしない。S25 の `bmcSettings.headNode` も `hasBmc: false`、`configureOnBoot: false` と表示される。

## ネットワーク設定

共通の IP・ゲートウェイ・DHCP 範囲と、インストーラーで確認した NIC の割り当ては [環境構成](environment.md#ネットワーク) に集約する。BCM のネットワーク名 `internalnet` / `externalnet` と、libvirt の仮想ネットワーク名は別の識別名である。

### 設定の変化

| 対象 | 途中画面 | 後続画面で確認した状態 |
|---|---|---|
| 内部ネットワーク | S12（19:37:42）は別のプライベート範囲・`/16`。旧アドレスの実値は省略 | S14（19:58:56）で環境構成の内部 `/24` と DHCP 動的範囲へ変更。S24 の `network` 配列でも一致 |
| 外部ネットワーク | S11（19:37:34）と S15（19:59:44）は `DHCP` にチェックあり | S16（20:05:23）でチェックなし、固定のネットワーク・マスク・ゲートウェイへ変更。S22、S24、S25 と整合 |
| ヘッド NIC | S17（20:06:45）で `enp1s0` を `internalnet`、`enp2s0` を `externalnet` に指定 | S29 の `headNode.interfaces` でも同じ組み合わせ。内部は `provisioning: true`、外部は `false` |

MAC はこれらの画面にないため、インストーラーで選んだ割り当てと実際の接続先が一致するかは別途照合する。

### アドレス以外の設定

| 項目 | internalnet | externalnet | 根拠 |
|---|---|---|---|
| Domain name | `<INTERNAL_DOMAIN>`（匿名化済み） | `<EXTERNAL_DOMAIN>`（匿名化済み） | S14、S16、S24、S25 |
| MTU | `1500` | `1500` | S14、S16、S24、S25 |
| Management network | チェックあり、`managementnetwork: true` | `managementnetwork: false` | S14、S24、S25 |
| Bootable network | チェックあり、`bootable: true` | `bootable: false` | S14、S24、S25 |
| 内部 Gateway 欄 | 未入力（`Optional` 表示）、JSON は `gateway: null` | 外部ゲートウェイは環境構成を参照 | S14、S24 |

内部 Gateway 欄の案内はヘッドノードを既定ゲートウェイとして使う旨を示す。`null` だけで計算ノードのゲートウェイが未設定と断定しない。ノードの実際の経路は起動後に確認する。

計算ノードの設定は `Interface: BOOTIF`、`Network: internalnet`、`IP offset: 0.0.0.10`（S18）。S30 でも `computeNode.interfaces` の `BOOTIF` / `internalnet` と `provisioning: true` を確認できる。これは起動 NIC に対する連続 IP 割り当ての指定で、6 台のノード別割り当て結果ではない。既存計画との違いは [環境構成](environment.md#ネットワーク) を参照する。

## ディスクと追加ソフトウェア

| 項目 | 表示値・選択状態 | 根拠 |
|---|---|---|
| ヘッドノードの導入ディスク | `/dev/vda (549GB Virtual I/O device)` を選択。Summary は `/dev/vda` | S19、S22 |
| Head node disk layout | `One big partition` | S20 |
| Compute nodes disk layout | `One big partition` | S20 |
| Additional software | `CUDA` にチェックあり。Summary も `CUDA` | S21、S22 |

**ヘッドノードのインストール対象は `/dev/vda` であり、導入を実行すると対象ディスクの既存データを上書きし得る。** 再実行する場合は VM と対象ディスクを確認する。計算ノードの `One big partition` は後続の OS 展開用の選択であり、この画面だけでは対象デバイス・各パーティション・サイズを確認できない。ワーカーの TopoLVM 用追加ディスクを OS 展開で初期化しないよう、展開前に対象範囲を確認する。

`One big partition` という選択名から、EFI・swap 等を含む実際のパーティション数や構成は断定しない。S28 の Show config に暗号化レイアウトの候補が写っているが、表示された 3 候補は `selected: false` であり、暗号化を選択した証跡ではない。

本環境は GPU を割り当てない計画だが、CUDA が選択されている事実はそのまま記録する。選択理由・実際に導入されたパッケージとバージョン・GPU なし構成での必要性は未確認。

## Summary・Show config の読み取り

S22（20:12:04）の Summary では、外部・内部 IP、外部ゲートウェイ、空欄の Nameservers、時刻設定、`None`、両機種 `Other`、`/dev/vda`、両方 `No BMC`、`CUDA` を確認できる。画面上の設定値は前節と [環境構成](environment.md) に整理したとおり。

S23～S30（20:14:19～20:15:43）は Deployment 画面を背景に Show config を表示している。背景に `Reboot` ボタンは見えるが、進行・結果の本文がダイアログに隠れている。したがって、**Deployment 画面への遷移と設定表示を確認した段階**として扱う。`Start` のクリック時刻、導入処理のログ・成否、再起動の実施は記録できない。

Show config の画像は JSON の一部ずつを写したもので、完全な設定エクスポートではない。設定項目と選択肢が混在するため、次のように読み分ける。

- `network` 配列（S24、S25）と `headNode.interfaces`（S29）を、それぞれの設定画面・Summary と照合する。
- S27 の `externalnet` に `DHCP` の文字列があるが、親オブジェクトが画面外にある。これを根拠に、固定 IP 設定から DHCP に戻ったとは判断しない。
- `environmentModules` は `selected: true` の Tcl modules を採用し、候補の Lmod や `bmcTypes`、未選択のディスクレイアウトを設定済みとして扱わない。
- S23 の `license` に `Temporary` と表示されるが、適用済みライセンスの有効性・ノード上限・期限は確認できない。確認方法は [製品資料](references.md#ライセンスと実バージョンの確認) を参照する。
- S29 には管理者パスワードの実値を含む項目があるため、JSON 全文や画像を公開用文書へ複製しない。

## 残る確認事項

以下は画面整理時点の確認課題。同日夜の調査で判明した進捗は [検証状況](validation.md) を参照し、未確認のままと重複管理しない。

| 対象 | 次に確認・記録する内容 |
|---|---|
| インストールと初回起動 | Deployment の完了・エラー全文、再起動後のログイン、BCM サービスの状態、実際の BCM / OS バージョン |
| NIC と外部通信 | MAC と内部・外部 NIC の対応、固定 IP・ゲートウェイの反映、DNS 計画との差、名前解決・時刻同期・外部疎通 |
| ノード登録と OS 展開 | VM・BCM ノード名・MAC・役割の対応、連続 IP 割り当てと予約計画の調整、DHCP・PXE 応答と 6 台の展開結果 |
| ディスク | ヘッドの実パーティション構成、計算ノードの展開先と TopoLVM 用追加ディスクの保護 |
| ソフトウェア・ライセンス | CUDA の選択意図と導入結果、7 VM 構成に対するライセンス条件 |

## 一次資料

すべて `input/30-bcm-install/` 配下のローカル資料で、Git 管理対象外。日時はファイル名に基づく。元画像を保持していない clone 環境では参照できない。

| ID | 一次資料のパス | 主な画面・内容 |
|---|---|---|
| S01 | `input/30-bcm-install/スクリーンショット 2026-09-22 173125.png` | NVIDIA EULA |
| S02 | `input/30-bcm-install/スクリーンショット 2026-09-22 173130.png` | Ubuntu ライセンス |
| S03 | `input/30-bcm-install/スクリーンショット 2026-09-22 173134.png` | Kernel modules |
| S04 | `input/30-bcm-install/スクリーンショット 2026-09-22 173141.png` | Hardware info |
| S05 | `input/30-bcm-install/スクリーンショット 2026-09-22 173315.png` | メディア整合性チェック |
| S06 | `input/30-bcm-install/スクリーンショット 2026-09-22 173424.png` | Cluster settings |
| S07 | `input/30-bcm-install/スクリーンショット 2026-09-22 173501.png` | HPC workload manager |
| S08 | `input/30-bcm-install/スクリーンショット 2026-09-22 173517.png` | Network topology |
| S09 | `input/30-bcm-install/スクリーンショット 2026-09-22 173723.png` | Head node settings |
| S10 | `input/30-bcm-install/スクリーンショット 2026-09-22 173839.png` | Compute nodes settings |
| S11 | `input/30-bcm-install/スクリーンショット 2026-09-22 193734.png` | 外部 DHCP 有効の途中画面 |
| S12 | `input/30-bcm-install/スクリーンショット 2026-09-22 193742.png` | 内部ネットワーク変更前 |
| S13 | `input/30-bcm-install/スクリーンショット 2026-09-22 193812.png` | BMC configuration |
| S14 | `input/30-bcm-install/スクリーンショット 2026-09-22 195856.png` | 内部ネットワーク変更後 |
| S15 | `input/30-bcm-install/スクリーンショット 2026-09-22 195944.png` | 外部 DHCP 有効の途中画面 |
| S16 | `input/30-bcm-install/スクリーンショット 2026-09-22 200523.png` | 外部固定設定への変更後 |
| S17 | `input/30-bcm-install/スクリーンショット 2026-09-22 200645.png` | Head node network interfaces |
| S18 | `input/30-bcm-install/スクリーンショット 2026-09-22 201113.png` | Compute nodes network interfaces |
| S19 | `input/30-bcm-install/スクリーンショット 2026-09-22 201126.png` | Installation drives |
| S20 | `input/30-bcm-install/スクリーンショット 2026-09-22 201146.png` | Disk layouts |
| S21 | `input/30-bcm-install/スクリーンショット 2026-09-22 201158.png` | Additional software |
| S22 | `input/30-bcm-install/スクリーンショット 2026-09-22 201204.png` | Summary |
| S23 | `input/30-bcm-install/スクリーンショット 2026-09-22 201419.png` | Show config: modules・NTP 等 |
| S24 | `input/30-bcm-install/スクリーンショット 2026-09-22 201437.png` | Show config: network 配列 |
| S25 | `input/30-bcm-install/スクリーンショット 2026-09-22 201444.png` | Show config: 外部ネットワーク・BMC |
| S26 | `input/30-bcm-install/スクリーンショット 2026-09-22 201501.png` | Show config: BMC 候補 |
| S27 | `input/30-bcm-install/スクリーンショット 2026-09-22 201511.png` | Show config: ネットワーク関連の断片 |
| S28 | `input/30-bcm-install/スクリーンショット 2026-09-22 201524.png` | Show config: 未選択のレイアウト候補 |
| S29 | `input/30-bcm-install/スクリーンショット 2026-09-22 201533.png` | Show config: headNode（認証情報を含む） |
| S30 | `input/30-bcm-install/スクリーンショット 2026-09-22 201543.png` | Show config: computeNode・clustername |

スクリーンショットのブラウザー URL には接続トークンがあり、S29 には管理者パスワードの実値も含まれる。原本は `input/` に保持し、URL・認証情報の転記や、画像の `docs/` への複製・埋め込みは行わない。
