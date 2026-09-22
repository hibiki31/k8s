# ワーカーの初回展開と TopoLVM 用 LVM の設計案

整理日: 2026-09-23（JST）。対象は BCM 名 node004～node006（ユーザーの node04～06）、対応する VM は [環境構成](environment.md#2026-09-22-の稼働後確認) を参照。**提案・静的検証の段階であり、ワーカーの設定変更・起動・ディスク初期化は未実施。** VM ごとの OS / 追加ディスクはともに 256 GiB。構成の正本は [VM 一覧](vm-list.md)、進捗は [検証状況](validation.md)。

## 結論と構成案

BCM の disksetup で VG を作る場合、最低 1 個の LV が必要。この環境の XSD と node-installer の静的検証でも確認した。一方、TopoLVM は事前作成済み VG を要求するが、事前 LV は要求していない。今回は BCM で初回の OS・LVM 作成を揃える案として、**4 MiB の予約 LV を 1 個残し、残りを VG の空き extents とする**構成を提案する。

| 項目 | 提案値・役割 |
|---|---|
| OS ディスク | 256 GiB、EFI 100 MiB + swap 16 GiB + 残り XFS `/`。今回の変更は追加ディスク側を中心とし、swap は既存の [Kubernetes 構築時の扱い](bcm-pxe-provisioning.md#kubernetes-と-swap) を継承 |
| TopoLVM ディスク | OS と別の 256 GiB、GPT + 全容量の `linux lvm` パーティション 1 個 |
| VG | 各ワーカーに独立した `vg_topolvm`。同名でもノード間共有 VG ではない |
| PE | `4M`（4 MiB） |
| 予約 LV | `bcm_seed`、`4M` = この案での 1 PE。ファイルシステム・マウント先なし |
| TopoLVM の割当元 | VG の未割当領域。`bcm_seed` の中やファイルシステムの空き容量ではない |
| LV の種類 | 通常の thick / linear。初期検証では thin pool を作らない |
| 空き容量の留保 | lvmd の `spare-gb: 10`。10 GiB を容量報告から差し引く設定で、予約 LV を作る設定ではない |
| PVC 用容量の目安 | 約 246 GiB 弱 / 台。実容量は GPT・PV/VG メタデータ・PE 丸め・seed・留保を差し引いて起動後に確認 |

`4M` は PE を 4 MiB とするこの設計での最小単位であり、BCM 全般の絶対最小 LV サイズという意味ではない。seed に `size=max` や全空き容量を割り当てると TopoLVM の作成領域がなくなるため、固定サイズにする。

TopoLVM の確認した実装では通常 LV も一覧に見えるが、PVC に対応する LV は LogicalVolume CR の UID 名で管理される。`bcm_seed` はそれと異なる固定名とする。通常の PVC 作成・削除で任意の既存 LV を回収する経路は見つからなかったが、これはソースに基づく共存の見込みで、採用版の実機確認は残る。

BCM の制約を避ける別案として、OS だけ BCM で展開し、起動後に追加ディスクの PV / VG を別途作成する方法もある。その場合は seed LV は不要。BCM による初回一括構築を重視するなら本案、VG 作成を別工程にできるなら後者が簡潔である。

## 初回作成用 XML 案

以下は自作の未適用テンプレート。**`/dev/OS_DISK` と `/dev/TOPO_DISK` は未解決のプレースホルダー**で、実デバイスではない。物理ホストの `virsh domblklist --details` / `dumpxml --inactive` のバックエンド・target と作成時用途を照合してから置換する。両ディスクは同容量なので、容量だけで識別しない。`vda` / `vdb` とも現時点では断定しない。FULL でこの XML を適用すると、指定した両ディスクを初期化する。

```xml
<?xml version="1.0"?>
<diskSetup>
  <device>
    <blockdev>/dev/OS_DISK</blockdev>
    <partitionTable>gpt</partitionTable>
    <partition id="os_efi" partitiontype="esp">
      <size>100M</size><type>linux</type><filesystem>fat</filesystem><mountPoint>/boot/efi</mountPoint>
    </partition>
    <partition id="os_swap"><size>16G</size><type>linux swap</type></partition>
    <partition id="os_root">
      <size>max</size><type>linux</type><filesystem>xfs</filesystem><mountPoint>/</mountPoint>
    </partition>
  </device>
  <device>
    <blockdev>/dev/TOPO_DISK</blockdev>
    <partitionTable>gpt</partitionTable>
    <partition id="topo_pv"><size>max</size><type>linux lvm</type></partition>
  </device>
  <volumeGroup>
    <name>vg_topolvm</name><extentSize>4M</extentSize>
    <physicalVolumes><member>topo_pv</member></physicalVolumes>
    <logicalVolumes><volume><name>bcm_seed</name><size>4M</size></volume></logicalVolumes>
  </volumeGroup>
</diskSetup>
```

BCM の `volumeGroup/physicalVolumes/member` は上の partition の `id` を参照する。LV の filesystem / mountPoint は省略可能で、seed をフォーマット・マウントする必要はない。スキーマ原本・製品テンプレートは転載せず、必要な要素から本環境向けの案を作成した。

OS と LVM に使うデバイスを限定する設定は、**node004～006 だけ**へ適用する。初回は node004 のノード単位 disksetup 上書きで検証し、合格後に node005・006 へ展開する案とする。現在の `default` カテゴリは cp1～3 を含む 6 台が共有しているため、本案のデータディスク定義をそのまま共有 default へ設定しない。将来ワーカー専用カテゴリへ集約する場合も、継承する他設定を照合する。

## 初回作成後のデータ保持

**初回作成用と運用用の disksetup を分ける。** 初回の VG・seed 作成を確認したら、OS の定義を同一に保ち、追加ディスクの `<device>` と `vg_topolvm` の `<volumeGroup>` を運用用 XML から外す案とする。VG や seed の実体を削除する操作ではない。運用用 XML も静的検証し、実機で保持試験を通してから PVC データを置く。

理由と限界:

- 初回 XML にデータディスクを残したまま FULL が走ると、追加ディスクのパーティション・PV も再作成され、TopoLVM データを失う。seed があるだけでは防げない。
- 現 node-installer のチェック実装は XML に記載した VG / LV を確認する。動的 LV が増えただけで不一致になる根拠は見つからなかった。一方、XML に記載した seed を実体だけ削除すると欠落として検出され得るため、その削除を必須工程にしない。
- 運用用 XML からデータディスク・VG を外すと、当該ディスクのパーティション・PV/VG メタデータの再作成経路から外れる。ただし node-installer には全体の device-mapper mapping を解除する処理があるため、「追加ディスクに一切触れない」とは保証しない。
- `datanode=yes` を対象ノードに設定する案を併用する。FULL の前に明示確認を要求する機能で、FULL を承認した後のデータ保持を保証するものではない。`AUTO` / `NOSYNC` 単独を保護策としない。
- 再起動時にも OS / データディスクの識別が同じであることが前提。明示的なディスク消去設定・カスタムスクリプト等がある場合は別途確認する。

この保持方針はインストール済み実装の限定調査に基づく提案で、AUTO 再起動・OS 再展開後の保持は未実証。BCM のファイル同期除外リストだけでパーティション初期化を防げるとは扱わない。

## 適用・確認の順序（未実行）

1. 物理ホストで worker1～3 の停止状態、内部 NIC / Multus NIC、OS / 追加ディスク、UEFI PXE 順序を照合する。追加ディスクは初期資料では空だが、今回内容を再確認していない。
2. node004 を先行対象にする。実デバイス名を確定した初回 XML を静的検証し、対象ノードだけへ設定する。`datanode=yes`、内部 MAC、BOOTIF の計画 IP も反映・再読確認する。MAC・IP の正本は [環境構成](environment.md#ネットワーク)。ワーカーの現行 `.14`～`.16` は計画 `.21`～`.23` への調整が必要。
3. worker1 だけを PXE 起動し、対象確認後に初回 FULL を実行する。BCM の UP・同期完了と [OS 基本確認](bcm-pxe-provisioning.md#5-展開と起動を確認する) に加え、下記の LVM 読み取りで OS 側の PV 混入がなく、VG・seed・十分な空き extents があることを確認する。
4. node004 の disksetup を OS だけの運用用 XML へ切り替える。実 VG / seed は残す。検証用の追加 LV と内容を用意して AUTO 再起動し、PV/VG/LV の識別子・LV 数・内容が保持されることを確認する。破壊可能な検証データだけでの OS FULL 再展開試験も別途行い、保持可否を確定する。
5. 合格した手順を node005・006 に適用する。Kubernetes 構築と TopoLVM の採用版・配置を確定後、3 ワーカーにだけ VG を参照する lvmd を配置する。最初の PVC 作成・書き込み・削除後にも seed と VG が残り、空き容量が期待どおり変わることを確認する。

起動後の各ワーカー上で実行する読み取り例（未実行）:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
pvs -o pv_name,vg_name,pv_size,pv_free
vgs -o vg_name,vg_size,vg_free,vg_extent_size,pv_count,lv_count
lvs -a -o vg_name,lv_name,lv_size,lv_attr,devices
```

確認条件は `vg_topolvm` の PV が追加ディスクだけ、初回 LV が `bcm_seed` 4 MiB の 1 個、VG 空きがほぼ全容量であること。後続の PVC 用 LV と区別して結果を保存する。

lvmd 設定案（未導入・採用版の schema / Helm values は導入時に再確認）:

```yaml
socket-name: /run/topolvm/lvmd.sock
device-classes:
  - name: default
    volume-group: vg_topolvm
    default: true
    spare-gb: 10
```

上記は lvmd 自体の設定形式で、Helm values の構造ではない。VG のないコントロールプレーンまで lvmd を配置しないよう、導入時にノードの選択条件を設定する。thin pool は指定しない。

## 今回実施した調査・静的検証

実行者は Codex と読み取り調査のサブエージェント。2026-09-23 01:38 JST に BCM ヘッドの管理権限で以下を読み取り、すべて終了コード 0。`main versioninfo` は Cluster Manager 11.0 / CMDaemon 3.1 / Build Index 165270。node004～006 は未登録 MAC・DOWN / unassigned、default カテゴリの OS 用 disksetup と default-image を継承していた。カテゴリは通常 AUTO / 新規 FULL。提案値はまだ保存していない。

```bash
cmsh -c 'main versioninfo'
cmsh -c 'device list'
cmsh -c 'category list'
cmsh -c 'category use default; get disksetup; get installmode; get newnodeinstallmode'
# 各 node004 / node005 / node006 に対して実行
cmsh -c 'device use node004; get category; get mac; get disksetup; get softwareimage; get installmode; get nextinstallmode; interfaces; list'
```

手順と結果:

1. `git status --short --untracked-files=all` で開始時に変更なし。README、VM 一覧、要件、環境構成、検証状況、PXE 手順、資料索引を `cat` / `rg` / `sed` で読んだ。`rg --files` でテンプレート・一時 PDF 読み取り環境を確認し、上記 BCM 読み取りを Python `subprocess.run` で実行、時刻・終了コード・出力を保存した。
2. ローカル Admin Manual を `/tmp/bcm-pdf-read` の pypdf で読み、BCM の XSD・同梱 LVM テンプレート・node-installer の `disks` を `rg` / `sed` で照合。`logicalVolumes` の `volume` は 1 個以上、filesystem は省略可能と確認した。保存用の `preserve` 等の属性は現在の XSD に見つからなかった。
3. Python で自作 XML を `/tmp/bcm-worker-lvm-4m.xml` に作り、下記 2 検証で終了コード 0。比較用に LV を除いた XML は xmllint 終了コード 3、子 volume 欠落で拒否された。初版は OS swap なしだったが、今回の変更範囲を追加ディスクに絞るため swap 16G を戻し、最終案でも両検証を再実行して成功した。これは構造検証であり、デバイスの実在や展開成功の確認ではない。
4. TopoLVM 公式 docs / ソースを Web と公開 GitHub API で参照。API で main の SHA を取得し、対象ソースとアーカイブを Python で読み取り、通常 LV の列挙、UID による管理対象の選択、削除経路、容量留保を調べた。アーカイブはメモリ内でのみ扱い、製品ソースをリポジトリへ転載しない。
5. 初回の `pdftotext` は未導入で終了 127、サブエージェントの sandbox 内 `cmsh main help` は接続不可で終了 1。存在しない探索先の `ls` は終了 2、`dpkg-query` は未検出の node-installer パッケージ名を含み全体終了 1 だが cmdaemon / libxml2-utils の版は取得。後者は `2.9.14+dfsg-1.3ubuntu3.7`。公開 BCM PDF は閲覧サイズ上限、固定 SHA の一部 Web URL は Cache miss。公開 API の最初の sandbox 取得も DNS failure だったが、ネットワークアクセス許可を伴う読み取りで成功した。これらを実確認成功と混同しない。
6. 本書と関連索引・環境構成の提案リンク・進捗・既存 PXE 手順を更新。資料索引の初回編集は想定した見出しがなく Python の assertion で停止したため、実際の見出しを確認して該当箇所だけ再実行した。[保守手順](repository-maintenance.md#保存前の確認コミット手順) に従いリンク・コードブロック・提案と実施済みの区別・ステージ済み差分・公開情報を確認してコミットする。一次資料は input に置き、実ヘッド名等を公開文書へ転記しない。実環境の変更・VM 起動・push は行わない。

実行した静的検証（BCM ヘッド、ソース確認により検出・初期化を行わない分岐を使用）:

```bash
xmllint --noout --schema /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd /tmp/bcm-worker-lvm-4m.xml
/cm/node-installer/scripts/disks -s /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd -x /tmp/bcm-worker-lvm-4m.xml validate nodetect
```

証跡は `input/70-worker-lvm/2026-09-23-bcm-worker-preflight.json`、自作 XML と検証要約を保存した同ディレクトリ、および本タスクのツール出力。実ディスクの PV / VG / LV 作成、再起動、TopoLVM の PVC 動作は未実施。

## 根拠と適用範囲

- BCM 11 Admin Manual: `input/10-bcm-installer-manual/admin-manual.pdf`、Revision `47eff3c`、2026-09-21。§3.13 pp.166–169、§5.4.4–5.4.6 pp.276–282（datanode は pp.279–280）、§D.1 pp.941–948（VG/LV は p.947）、§D.3 pp.952–955、§D.7 pp.959–960、§D.11 pp.962–963。紙面・PDF ページ一致。[公式配布先](https://docs.nvidia.com/base-command-manager/manuals/11/admin-manual.pdf)。
- 同梱実装: `/cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd`、`/cm/node-installer/scripts/disks`。LV 解釈・作成・action_create・action_check・validate nodetect の対象箇所を確認。全文転載せず仕様・観測結果を要約。
- TopoLVM: 2026-09-23 参照、main commit `6560b19387d0cd4da230dc6113e745b4ac74f53b`。採用バージョンは未定。[Getting Started](https://github.com/topolvm/topolvm/blob/6560b19387d0cd4da230dc6113e745b4ac74f53b/docs/getting-started.md)、[lvmd 設定](https://github.com/topolvm/topolvm/blob/6560b19387d0cd4da230dc6113e745b4ac74f53b/docs/lvmd.md)、[LV controller](https://github.com/topolvm/topolvm/blob/6560b19387d0cd4da230dc6113e745b4ac74f53b/internal/controller/logicalvolume_controller.go)、[VG service](https://github.com/topolvm/topolvm/blob/6560b19387d0cd4da230dc6113e745b4ac74f53b/internal/lvmd/vgservice.go)。seed の共存はこの実装からの判断で、公式の BCM 連携認定を意味しない。
