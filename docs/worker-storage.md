# ワーカーの初回展開と TopoLVM 用 LVM の手順

整理日: 2026-09-23（JST）。対象は BCM 名 node004～node006（ユーザーの node04～06）、対応する VM は [環境構成](environment.md#2026-09-22-の稼働後確認) を参照。利用者の設計案了承を受け、適用手順を具体化した。**ワーカーの設定変更・起動・ディスク初期化は未実施。** VM ごとの OS / 追加ディスクはともに 256 GiB。構成の正本は [VM 一覧](vm-list.md)、進捗は [検証状況](validation.md)。

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

以下は BCM 11.0 / CMDaemon 3.1（Build Index 165270）で構文・XML を確認した手順。実施者は利用者を想定し、各手順の実行日時・結果は実施後に記録する。物理ホストの libvirt 管理権限、BCM ヘッドと対象ノードの root 権限が必要。まず node004 だけを進める。node001～003 と共有 `default` カテゴリは変更しない。

### 1. 物理ホストでディスクと NIC を確定する

**KVM / libvirt 物理ホスト上**で実行する。

```bash
virsh domstate tk8s-worker1
virsh domiflist tk8s-worker1 --inactive
virsh domblklist tk8s-worker1 --inactive --details
virsh dumpxml tk8s-worker1 --inactive
```

確認条件:

- VM が停止中。既に起動・展開されていれば、その状態を調べてから進める。
- 内部 NIC は `tk8s-internal`、MAC は環境構成の worker1 行と一致。Multus NIC と区別する。
- OS と TopoLVM 用の各 256 GiB ディスクについて、バックエンドの作成用途と guest target の対応が確定している。初回 FULL では両方を消去するため、保存すべき内容がないことを確認する。
- UEFI / Secure Boot 無効 / 内部 NIC の IPv4 PXE 優先を確認する。

例えば OS が `vda`、追加が `vdb` と照合できた場合だけ、後続 XML を `/dev/vda`、`/dev/vdb` にする。容量や接続順だけで推測しない。この照合結果が得られるまで MAC 登録・起動へ進まない。

### 2. BCM ヘッドで初回用・運用用 XML を用意する

**BCM ヘッド、リポジトリルート**で実行する。以下の `/root/k8s` は配置先に合わせる。コピー元は [初回用テンプレート](examples/worker-initial-lvm.xml) と [運用用テンプレート](examples/worker-os-only.xml)。実際の適用ファイルは Git 管理外の `input/` に保存する。

```bash
cd /root/k8s
umask 077
mkdir -p input/70-worker-lvm
cp docs/examples/worker-initial-lvm.xml input/70-worker-lvm/node004-initial.xml
cp docs/examples/worker-os-only.xml input/70-worker-lvm/node004-os-only.xml
vi input/70-worker-lvm/node004-initial.xml input/70-worker-lvm/node004-os-only.xml
```

両ファイルの `/dev/OS_DISK` を確定した OS デバイスへ、初回用の `/dev/TOPO_DISK` を確定した追加デバイスへ置換する。これはワーカー内のデバイス名であり、BCM ヘッドのディスク名ではない。2 ファイルの OS 定義を一致させ、運用用には OS 以外の device / volumeGroup を含めない。以下はファイル内容だけを検査し、ディスク操作は行わない。

```bash
python3 - <<'PY'
from pathlib import Path
import xml.etree.ElementTree as ET
base = Path('input/70-worker-lvm')
initial = ET.parse(base / 'node004-initial.xml').getroot()
runtime = ET.parse(base / 'node004-os-only.xml').getroot()
def structure(e):
    return e.tag, e.attrib, (e.text or '').strip(), [structure(c) for c in e]
devices = initial.findall('device')
assert len(devices) == 2
assert len(runtime.findall('device')) == 1 and runtime.find('volumeGroup') is None
assert structure(devices[0]) == structure(runtime.find('device'))
paths = [d.findtext('blockdev') for d in devices]
assert len(set(paths)) == 2
assert all(p and p.startswith('/dev/') and 'DISK' not in p for p in paths)
assert initial.findtext('volumeGroup/name') == 'vg_topolvm'
assert initial.findtext('volumeGroup/logicalVolumes/volume/name') == 'bcm_seed'
assert initial.findtext('volumeGroup/logicalVolumes/volume/size') == '4M'
print('OS:', paths[0], 'TopoLVM:', paths[1], 'OS definitions match')
PY

xmllint --noout --schema /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd input/70-worker-lvm/node004-initial.xml
/cm/node-installer/scripts/disks -s /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd -x input/70-worker-lvm/node004-initial.xml validate nodetect
xmllint --noout --schema /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd input/70-worker-lvm/node004-os-only.xml
/cm/node-installer/scripts/disks -s /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd -x input/70-worker-lvm/node004-os-only.xml validate nodetect
```

全コマンド成功を確認してから進む。`validate nodetect` は構造検証であり、実ディスクの対応・空き容量・初期化してよい状態は保証しない。

### 3. node004 の設定を保存し、最後に MAC を登録する

**BCM ヘッド上**で、現在値を保存して消去予約とカスタムスクリプトを確認する。VM は停止したままにする。

```bash
cmsh -c 'device list'
cmsh -c 'device use node004; get disksetup' > input/70-worker-lvm/node004-before-disksetup.txt
cmsh -c 'device use node004; get mac; get datanode; get installmode; get nextinstallmode; get blockdevicesclearedonnextboot; get initializescript; get finalizescript; interfaces; list'
cmsh -c 'category use default; get initializescript; get finalizescript'
```

`blockdevicesclearedonnextboot` は空であること。これは `datanode` / インストールモードによらず消去し得る予約なので、値があればその意図を調べ、解消するまで起動しない。initialize / finalize スクリプトも空、または内容を確認済みで追加ディスクを消去しないことが条件。node004 は MAC 未登録で、計画 IP が他ノードと重複しないことを照合する。

次は `cmsh` を起動し、**対話モード**で 1 行ずつ実行する。エラーがあれば commit せず原因を確認する。

```text
device use node004
set disksetup /root/k8s/input/70-worker-lvm/node004-initial.xml
set datanode yes
set installmode AUTO
set nextinstallmode FULL
validate
get disksetup
get datanode
get installmode
get nextinstallmode
```

node004 が選択され、XML の 2 ディスクと 4M seed、`yes` / `AUTO` / `FULL` が正しいことを確認したら、同じセッションで保存して終了する。

```text
commit
quit
```

`set disksetup /絶対パス/file.xml` は XML の内容を BCM へ取り込む。後でファイルだけを編集しても BCM の保存値は変わらない。`nextinstallmode FULL` は初回に限る指定とし、通常の installmode は AUTO にする。

内部 MAC を手順 1 で照合できた場合に、IP、MAC の順で登録する。以下は [環境構成](environment.md#ネットワーク) の node004 計画値。

```bash
cmsh -c 'device; interfaces node004; use BOOTIF; set ip 172.30.65.21; commit'
cmsh -c 'device use node004; set mac 52:54:00:65:00:05; commit'
cmsh -c 'device use node004; get disksetup; get datanode; get installmode; get nextinstallmode; get blockdevicesclearedonnextboot'
cmsh -c 'device list'
cmsh -c 'device; interfaces node004; list'
```

保存後の実値を再読し、BOOTIF が `internalnet` / 予定 IP、MAC が内部 NIC、XML が対象の 2 ディスクに限定されていることを確認する。

### 4. worker1 を起動し、初回 FULL を確認する

**物理ホスト上**で実行する。

```bash
virsh start tk8s-worker1
```

VM コンソールで内部 NIC の UEFI IPv4 PXE → AUTO と進み、ノード確認画面が出たら node004・内部 MAC・予定 IP を照合する。`datanode=yes` による FULL の確認待ちが出たら、今回の初回作成で両ディスクを消去してよいことを確認して、そのノードだけ承認する。対象が違う、または FULL の理由が不明なら承認しない。

**BCM ヘッド上**で状態と同期ログを確認する。

```bash
cmsh -c 'device list'
cmsh -c 'device synclog node004'
```

同期完了・UP・コンソール上の OS 起動後、コンソールの root シェルで `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` を取得する。BCM ヘッドから `ssh root@node004` を実行し、初回提示される指紋を照合して登録する。SSH のホスト鍵確認を無効化しない。

### 5. node004 上で OS と LVM を確認する

以下は **SSH 接続先 node004 上**。`pvs` などが存在しなければ LVM 管理ツールの導入・イメージ反映を別途確認し、未確認のまま進めない。

```bash
hostname
ip -br addr
ip route
findmnt -no SOURCE,FSTYPE /
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
swapon --show
systemctl --failed
getent ahostsv4 docs.nvidia.com
curl -4 -I --connect-timeout 5 --max-time 15 -sS -o /dev/null -w 'HTTPS status: %{http_code}\n' https://docs.nvidia.com/
pvs -o pv_name,vg_name,pv_size,pv_free
vgs -o vg_name,vg_size,vg_free,vg_extent_size,pv_count,lv_count
lvs -a -o vg_name,lv_name,lv_size,lv_attr,devices
```

合格条件は予定 IP / ゲートウェイ、OS ディスク上の XFS ルート、失敗サービス 0、DNS・HTTPS 成功に加えて次のとおり。

- `vg_topolvm` の PV は追加ディスクのパーティション 1 個だけ。OS ディスクが混入していない。
- VG の PE は 4 MiB、LV は `bcm_seed` 4 MiB の 1 個だけ。filesystem / mountpoint なし。
- VG のほぼ全容量が未割当。`spare-gb: 10` は後続 lvmd の設定なので、ここではまだ差し引かれない。

swap 16 GiB は既存 OS レイアウトを維持した結果として記録し、[Kubernetes 構築時の確認](bcm-pxe-provisioning.md#kubernetes-と-swap) は別途行う。

### 6. BCM の disksetup を運用用へ切り替える

手順 5 の合格後、**BCM ヘッドの対話 cmsh** で実行する。実 VG / seed は削除しない。

```text
device use node004
set disksetup /root/k8s/input/70-worker-lvm/node004-os-only.xml
validate
get disksetup
get datanode
get installmode
get nextinstallmode
get blockdevicesclearedonnextboot
```

XML は同じ OS 定義だけ、`datanode=yes`、通常 AUTO、nextinstallmode と消去予約は空であることを確認し、`commit` → `quit`。初回 FULL 後も nextinstallmode が残っていれば、再起動せず理由を調べる。保存後に `cmsh -c 'device use node004; get disksetup'` で運用用の内容を再読する。**この切替前に再展開を試さない。**

### 7. 検証用 LV で AUTO 再起動・OS 再展開後の保持を試す

実 PVC データを置く前に node004 で行う。seed は残し、別の破壊可能なテスト LV を作る。**node004 上**で同名 LV が存在しないことを `lvs` で確認後、作成する。既に存在する場合は上書きせず由来を確認する。

```bash
lvcreate -L 16M -n bcm_persist_test vg_topolvm
```

**直前の lvcreate が成功した場合だけ**、新規テスト LV 全体へ書き込む。OS ディスクや PV デバイスを指定しない。

```bash
dd if=/dev/urandom of=/dev/vg_topolvm/bcm_persist_test bs=1M count=16 iflag=fullblock conv=fsync
```

比較用の記録は OS FULL で消えない **BCM ヘッドの `input/`** へ保存する。例えば次の読み取りスクリプトを `input/70-worker-lvm/node004-lvm-snapshot.sh` としてヘッドに保存する。

```bash
#!/bin/bash
set -eu
export LC_ALL=C
pvs --reportformat basic --noheadings --units b --nosuffix -S vg_name=vg_topolvm -o pv_name,pv_uuid,vg_name,pv_size --sort pv_name
vgs --reportformat basic --noheadings --units b --nosuffix vg_topolvm -o vg_name,vg_uuid,vg_size,vg_free,vg_extent_size,pv_count,lv_count
lvs --reportformat basic --noheadings --units b --nosuffix vg_topolvm -o lv_name,lv_uuid,lv_size,devices --sort lv_name
test "$(blockdev --getsize64 /dev/vg_topolvm/bcm_persist_test)" = 16777216
sha256sum /dev/vg_topolvm/bcm_persist_test
```

ヘッドで以下を実行し、終了コード 0、PV / VG 各 1、LV 2 個、末尾にハッシュがあることを確認する。取得失敗を空の基準値として使わない。SSH ホスト鍵は手順 4 で確認済みが前提。

```bash
ssh -o StrictHostKeyChecking=yes root@node004 'bash -s' < input/70-worker-lvm/node004-lvm-snapshot.sh > input/70-worker-lvm/node004-before.txt
```

次の順で 2 回試験する。再起動は node004 上の `systemctl reboot` を使い、PXE を経由したことをコンソールと synclog で確認する。

1. **通常 AUTO**: 手順 6 の設定・消去予約・フックを再確認して再起動。予期しない FULL の確認待ちが出たら承認せず、理由を調べる。UP 後に同じスクリプトを使い、出力先だけ `node004-after-auto.txt` にして取得する。
2. **OS だけの FULL**: AUTO の保持合格後、BCM の保存済み disksetup が OS だけであることを再読する。`cmsh -c 'device use node004; set nextinstallmode FULL; commit'` とし、node004 を再起動。OS 上の内容は消去される試験なので、結果・必要なログをヘッドへ退避済みとする。コンソールで node004 の FULL を明示承認する。UP 後に出力先 `node004-after-full.txt` で取得し、nextinstallmode が空に戻ることも確認する。

FULL 後の SSH ホスト鍵が変わった場合はコンソールで再照合し、警告を無条件に回避しない。いずれの試験もまず `pvs` / `vgs` / `lvs -a -o lv_name,lv_uuid,lv_attr,devices vg_topolvm` の起動直後の結果をヘッド側へ保存する。VG / LV の識別子が基準と一致するが LV が inactive の場合は、node004 上で `vgchange -ay --activationmode complete vg_topolvm`、`udevadm settle`、`test -b /dev/vg_topolvm/bcm_persist_test` の順に有効化・確認してから取得する。これは読み取りと異なり活性状態を変える操作である。VG / LV が見つからない場合に作り直す操作はしない。

運用用 XML に VG 定義がない場合、現 node-installer の VG 有効化処理は省略される。OS の自動有効化は未確認であり、手動有効化が必要だった事実は保持の成否と分けて記録し、TopoLVM 導入前に解決する。`lv_attr` の active / open 状態は起動時に変わり得るため、上の比較用スクリプトでは属性全体を比較対象にしていない。

**BCM ヘッド上**で比較する。

```bash
diff -u input/70-worker-lvm/node004-before.txt input/70-worker-lvm/node004-after-auto.txt
diff -u input/70-worker-lvm/node004-before.txt input/70-worker-lvm/node004-after-full.txt
```

両方終了コード 0・差分なしが期待結果。PV/VG/LV の識別子・サイズ・個数と LV の全内容が同一であることを確認する。デバイス名だけが変わった場合も、パス固定の disksetup に影響するため合格扱いにせず原因を調べる。UUID・ハッシュの実値は Git 管理文書へ転載しない。

両試験合格後に **node004 上**で `lvremove /dev/vg_topolvm/bcm_persist_test` を実行し、対象名を確認して削除を承認する。`bcm_seed` は残す。LV 1 個と空き容量の回復を確認する。

### 8. node005・006 へ展開し、その後に TopoLVM を導入する

node004 の合格後、[環境構成の MAC・IP 対応](environment.md#ネットワーク) を使い、worker2 → worker3 の順で手順 1～6 を適用する。各 VM でディスク用途・target を照合し、ファイル名・BCM ノード名・VM 名・IP・MAC を対象ごとに変更する。node004 の実デバイス名を無確認で流用しない。各台の初回展開・OS / LVM・運用用への切替・通常再起動後の保持を記録する。

Kubernetes 構築と TopoLVM の採用版・配置を確定後、3 ワーカーにだけ VG を参照する lvmd を配置する。最初の PVC 作成・書き込み・削除後にも seed と VG が残り、空き容量が期待どおり変わることを確認する。

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

## 2026-09-23: 適用手順の具体化と構文確認

実行者は Codex と読み取りレビューのサブエージェント。利用者からは設計案の了承と手順提示の依頼を受けたが、この段階で新たなワーカー操作の実行報告はない。BCM ヘッド上の root 権限で、02:02～02:04 JST に次の読み取りを実行し、すべて終了コード 0。バージョンは前節の BCM 11.0 / Build 165270 を引き継ぎ、今回再照会していない。

```bash
cmsh -c 'device help set'
cmsh -c 'device help validate'
cmsh -c 'device help commit'
cmsh -c 'device use node004; get datanode; get installmode; get nextinstallmode; get blockdevicesclearedonnextboot'
cmsh -c 'category use default; get initializescript; get finalizescript'
cmsh -c 'device use node004; get initializescript; get finalizescript'
```

観測結果は node004 の datanode が `no`、ノード固有 installmode / nextinstallmode / 消去予約は空、node004 と default カテゴリの initialize / finalize スクリプトも空。値の変更は行っていない。証跡は Git 管理外の `input/70-worker-lvm/2026-09-23-worker-procedure-help.json`（Python subprocess で終了コード・出力・時刻を保存）。node005・006 の同項目は今回未照会。

続けて実施した手順と結果（個々の時刻は未記録）:

1. 開始時の `git status --short --untracked-files=all` は変更なし。README・本書・環境構成・VM 一覧・PXE 手順・進捗・保守手順を `cat` / `rg` / `sed` で読み、前提を照合した。途中、存在しない `docs/bcm-pxe-boot.md` への sed は終了 2。正しい `docs/bcm-pxe-provisioning.md` を読み直して成功した。
2. `/tmp/bcm-pdf-read` の pypdf、既存の一時抽出テキスト、`rg` / `sed` で Admin Manual の pp.166–169・278–282・947 と XSD / node-installer を照合。p.169 のファイルによる disksetup 取込みと p.281 の明示消去予約の扱いを確認した。OS-only XML で VG 有効化経路が省略されることは `disks` の action_mount / action_check を読んで確認した。
3. 前節の自作 XML から [初回用](examples/worker-initial-lvm.xml) を保存し、Python ElementTree で追加 device と volumeGroup だけを除いた [運用用](examples/worker-os-only.xml) を作成。両方に対し、下記の構造検証を実行して成功した。プレースホルダーのままの検証であり、デバイスの存在確認・実初期化ではない。
4. サブエージェントが `command -v pvs` で LVM コマンドの存在を確認した。`pvs` / `vgs` / `lvs` の `-o help` と `--readonly -o help` は sandbox 内のロック初期化に失敗（後者各終了 5）。ロック設定を変更せず、`rg --files /usr/share/man/man8`、Python gzip / pathlib によるインストール済み man と `/usr/sbin/lvm` の文字列の読み取りで列名・active 属性・activationmode の意味を照合した。これは実ノードでの LVM 情報取得成功を意味しない。
5. 本書を適用順・期待結果・失敗時の停止条件・保持試験まで拡張し、README・既存 PXE 案内・進捗を更新した。手順中の初期化・起動・LV 作成・vgchange は未実行。保存時は [保守手順](repository-maintenance.md#保存前の確認コミット手順) に沿い、Markdown リンク・ブロック、XML、実行記録との区別、ステージ済み内容と公開情報を確認してコミットする。
6. Python の pathlib / re / unicodedata で変更した Markdown 4 文書の相対リンク・アンカー 118 件とコードブロックを確認し、`bash -n` で本書の bash 例を実行せず構文解析した。ElementTree で両 XML の OS 定義の一致と本文 XML・ファイルの一致を確認。すべて成功し、`git diff --check` もエラーなし。サブエージェントは本書と XML 2 個を再読し、適用順と保持試験に重大な不足なしと確認した。`git ls-files -- input` は空、`git check-ignore -v` は読み取り証跡が `/input/` で除外されることを示した。

実行した静的検証（各ファイルに 2 コマンド、計 4 コマンド。全成功）:

```bash
xmllint --noout --schema /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd docs/examples/worker-initial-lvm.xml
/cm/node-installer/scripts/disks -s /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd -x docs/examples/worker-initial-lvm.xml validate nodetect
xmllint --noout --schema /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd docs/examples/worker-os-only.xml
/cm/node-installer/scripts/disks -s /cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd -x docs/examples/worker-os-only.xml validate nodetect
```

公開文書には匿名化した実行場所と既存の公開可能な検証用値を使い、実ヘッド名・ディスクバックエンド・UUID・指紋・認証情報は追加しない。実ディスクの照合、BCM 設定適用、初回作成、AUTO / FULL 後の保持・活性化、TopoLVM 連携は引き続き未確認。公開・push と過去の履歴全体の再監査は今回の対象外。

## 根拠と適用範囲

- BCM 11 Admin Manual: `input/10-bcm-installer-manual/admin-manual.pdf`、Revision `47eff3c`、2026-09-21。§3.13 pp.166–169、§5.4.4–5.4.6 pp.276–282（datanode は pp.279–280）、§D.1 pp.941–948（VG/LV は p.947）、§D.3 pp.952–955、§D.7 pp.959–960、§D.11 pp.962–963。紙面・PDF ページ一致。[公式配布先](https://docs.nvidia.com/base-command-manager/manuals/11/admin-manual.pdf)。
- 同梱実装: `/cm/local/apps/cmd/etc/htdocs/xsd/disks.xsd`、`/cm/node-installer/scripts/disks`。LV 解釈・作成・action_create・action_check・validate nodetect の対象箇所を確認。全文転載せず仕様・観測結果を要約。
- TopoLVM: 2026-09-23 参照、main commit `6560b19387d0cd4da230dc6113e745b4ac74f53b`。採用バージョンは未定。[Getting Started](https://github.com/topolvm/topolvm/blob/6560b19387d0cd4da230dc6113e745b4ac74f53b/docs/getting-started.md)、[lvmd 設定](https://github.com/topolvm/topolvm/blob/6560b19387d0cd4da230dc6113e745b4ac74f53b/docs/lvmd.md)、[LV controller](https://github.com/topolvm/topolvm/blob/6560b19387d0cd4da230dc6113e745b4ac74f53b/internal/controller/logicalvolume_controller.go)、[VG service](https://github.com/topolvm/topolvm/blob/6560b19387d0cd4da230dc6113e745b4ac74f53b/internal/lvmd/vgservice.go)。seed の共存はこの実装からの判断で、公式の BCM 連携認定を意味しない。
