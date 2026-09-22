# BCM による PXE・OS プロビジョニング

確認日: 2026-09-22（JST）。BCM ヘッドノード上の読み取り専用調査と、BCM 11 の製品資料に基づく。以下の設定変更・VM 起動・OS 展開手順は **未実行**。実際の進捗は [検証状況](validation.md)、ネットワークの実測値・割り当て計画は [環境構成](environment.md#2026-09-22-の稼働後確認) を参照する。

## 今回確認した前提

- CMDaemon、DHCP、DNS、HTTP、NFS が稼働。TFTP は `tftpd.socket` が UDP 69 を待ち受け、UEFI 用の `syslinux.efi` も存在する。`tftpd.service` 単体の `inactive` はソケット起動待ちの状態と区別する。
- `default-image` が存在し、カーネルは `6.8.0-106-generic`、ロックなし。ヘッドに `boot` と `provisioning` ロールがある。実際のイメージ転送・起動成功は未確認。
- 既定の `node001`～`node006` は全台 `DOWN, unassigned`、MAC 未登録。`device newnodes` に待機中のノードはない。この状態だけで VM の電源状態は断定しない。
- 同日夜に [ライセンス登録](bcm-licensing.md) を完了し、ヘッドを含む 7 台を扱えることを確認した。現在値は [検証状況](validation.md) を参照。最初の 1 台を確認してから残りへ進む順序は、展開設定を確かめるために維持する。
- ヘッドの NIC と MAC の対応は、利用者提供の libvirt 出力と照合済み。当初資料の MAC 対応を訂正し、現在の NIC 設定は維持する。cp1 の同一内部ネットワークへの接続定義と停止状態も確認した。詳細は [仮想化ホスト側の確認](environment.md#仮想化ホスト側の接続確認) を参照。
- `default` カテゴリは `newnodeinstallmode=FULL`、`installmode=AUTO`。新規ノードはディスクの再作成を伴う。`AUTO` も不一致時には `FULL` になるため、データ保護の代わりにはならない。

## 1. 仮想化ホストで接続とディスクを確認する

以下は **KVM / libvirt 物理ホスト上**の読み取り専用コマンド例。BCM VM 上では実行しない。VM が動いている場合は現在の構成と永続構成の両方を照合する。

```bash
virsh domiflist tk8s-bcm
virsh domiflist tk8s-bcm --inactive
virsh domiflist tk8s-cp1
virsh domstate tk8s-cp1
virsh domblklist tk8s-cp1 --details
virsh domblkinfo tk8s-cp1 vda
virsh dumpxml tk8s-cp1
virsh net-dumpxml tk8s-internal
```

確認条件:

- BCM の **実際の内部インターフェイス `enp1s0`** と、対象ノードの PXE NIC が同じ `tk8s-internal` / `tk8s-int` に接続されること。MAC 対応は [環境構成](environment.md#2026-09-22-の稼働後確認) を使う。資料の MAC 名称だけを理由に BCM の NIC 設定を交換しない。
- `tk8s-internal` で libvirt の DHCP が動作せず、BCM だけが DHCP を提供すること。
- `tk8s-cp1` の内部 NIC の MAC が計画と一致すること。UEFI・Secure Boot 無効、内部 NIC のネットワーク起動を優先すること。
- `tk8s-cp1` の OS ディスクが virtio の `vda`、容量 128 GiB であること。対象ディスクの内容は展開で消去される。
- ワーカーは `domblklist` と XML で OS 用と TopoLVM 用のバックエンドを識別する。両方 256 GiB のため、容量だけでは識別できない。追加ディスクが `vdb` であることも推測で決めない。

2026-09-22 の利用者提供出力で、BCM の内部・外部 NIC と cp1 の接続、cp1 の停止状態、`vda` 1 台、内部ネットワークの DHCP 定義なしを確認した。ヘッドの接続は実測と一致し、NIC 設定の交換は不要。容量・起動設定・ヘッドの永続構成は今回の出力では未確認なので、残る確認を上のコマンドや VM 設定画面で行う。`domblkinfo` の Capacity は仮想容量であり、qcow2 の実消費量とは区別する。本調査では物理ホストへの接続・修正は行っていない。

## 2. 最初の 1 台を BCM の既存定義へ登録する

以下は **BCM ヘッドノード上**で実行する未実行の設定例。手順 1 で MAC が一致することを確認し、対象 VM が停止している状態で行う。MAC 登録後は起動したノードの展開が進み得る。

最初は VM `tk8s-cp1` を既存定義 `node001` に対応させる。VM 名と BCM 内のホスト名は別であり、この手順では改名しない。割り当て表は [環境構成](environment.md#2026-09-22-の稼働後確認) を参照する。

```bash
# 読み取り: MAC 未登録・対象定義・カテゴリを再確認
cmsh -c 'device list'
cmsh -c 'category use default; get softwareimage; get newnodeinstallmode; get installmode; get disksetup'

# 設定変更: tk8s-cp1 の内部 NIC を node001 に対応付ける
cmsh -c 'device use node001; set mac 52:54:00:65:00:02; commit'

# 読み取り: node001 の BOOTIF は計画どおり 172.30.65.11 であること
cmsh -c 'device; interfaces node001; list'
```

`set mac`、インターフェイスの `set ip` は実機の `help set` で項目名を確認した。設定変更そのものは試していない。

## 3. 展開対象を OS ディスクだけに限定する

現在の既定レイアウトは、複数のデバイス候補を含む。`/dev/vda` に加え、クラウドモード用の `/dev/vdb` 等の候補もある。これはすべての候補が同時に初期化されることを意味しないが、ワーカーの追加ディスクの保護を保証する根拠にもならない。

**BCM ヘッドノード上**で `node001` のレイアウトを編集する未実行例:

```text
cmsh
device use node001
set disksetup
```

開いたエディターで既存 XML の `<device>` 内の `<blockdev>` 候補を、確認済みの OS ディスク **`<blockdev>/dev/vda</blockdev>` 1 行だけ**にする。既存の EFI 100M、swap 16G、残り XFS `/` のパーティション定義は保持する。保存後に以下で内容を確認してコミットする。

```text
get disksetup
commit
quit
```

この `commit` は BCM 設定の保存であり、Git コミットではない。設定保存後、PXE 起動した時点で対象ディスクの初期化・展開が行われる。デバイス名が `vda` でない場合は実際に識別した OS ディスクに合わせ、追加ディスクを含めない。

後続の 5 台にも同じ対象限定を適用する。ノード単位の `disksetup` はカテゴリ設定より優先されるため、`node001` の編集だけでは他の 5 台には反映されない。ワーカーは初回起動時に追加ディスクを外した構成で OS 展開する方法もあるが、いずれの場合もバックエンドを識別し、後から追加したディスクを再展開で消さない設定を維持する。

## 4. tk8s-cp1 だけを PXE 起動する

**仮想化ホスト上**で、停止中の対象 VM を起動する。ネットワーク優先の UEFI 起動順が設定済みであることが前提。

```bash
virsh start tk8s-cp1
```

noVNC 等の VM コンソールで、内部 NIC の **UEFI IPv4 PXE** を選択し、DHCP → ブートローダー → カーネル・initramfs → BCM node-installer → OS 展開の順に確認する。ISO インストーラーを再度起動する必要はない。

BCM の PXE メニューでは通常の `AUTO` を使用する。新規ノードにはカテゴリの `FULL` が適用されることを理解し、対象 VM・OS ディスクの確認を済ませておく。全台に `FULL` を永続設定する必要はない。

未知ノードの選択画面で停止したら、コンソールの MAC と `node001` に登録した MAC を再確認する。必要なら BCM 上で `cmsh -c 'device newnodes'` を実行する。MAC が期待した 1 台に一致するときだけコンソールの `Manually select node` で `node001` を選択する。出現順だけで一括割り当てしない。

## 5. 展開と起動を確認する

**BCM ヘッドノード上**の監視例。ログは起動処理が進んでから作られる場合がある。

```bash
journalctl -u dhcpd -f
tail -F /var/log/node-installer /var/log/cmdaemon
```

別端末で確認する:

```bash
cmsh -c 'device list'
cmsh -c 'device synclog node001'
ping -c 3 172.30.65.11
ssh root@172.30.65.11
```

SSH では接続先ホスト鍵を確認する。ヘッドに設置した利用者の SSH 公開鍵が、ソフトウェアイメージや計算ノードにも配布済みとは限らない。ログインできない場合は鍵配布と sshd の設定を別途確認する。

**展開後の node001 上**で確認する:

```bash
hostname
cat /etc/os-release
ip -br addr
ip route
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
systemctl --failed
getent ahostsv4 docs.nvidia.com
```

合格条件は、BCM の `UP` 表示、OS 展開ログに致命的エラーなし、期待した IP、OS ディスクからの稼働、管理ログイン、必要な名前解決・外部通信の確認。ヘッド側の NAT 設定があるだけでは、計算ノードからの外部疎通成功とはしない。

DHCP 応答がなければ内部 L2 接続・競合 DHCP・ファイアウォールを確認する。DHCP まで進み TFTP で停止する場合は、UEFI 用ファイル、UDP 69、TFTP の後続通信とサーバーログを確認する。イメージ転送段階なら NFS・provisioning ロール・`device synclog` を確認する。

## 6. 最初の 1 台の確認後に残り 5 台へ進む

ヘッドを含む 7 台を扱えるライセンスは適用・確認済み。期間を空けて作業する場合は `cmsh -c 'main licenseinfo'` と `verify-license verify` で再確認する。出力にはライセンス識別情報があるため、そのまま公開しない。

各 VM の MAC を実接続と照合してから、手順 2 と同様に `node002`～`node006` へ登録する。対応する VM・MAC・IP は [環境構成](environment.md#2026-09-22-の稼働後確認) に集約する。

ワーカーは現在の連続 IP を計画に合わせて変更する。以下は **BCM ヘッドノード上**の未実行例（VM が停止中、既存の IP 使用がないことを確認した後）。

```bash
cmsh -c 'device; interfaces node004; use BOOTIF; set ip 172.30.65.21; commit'
cmsh -c 'device; interfaces node005; use BOOTIF; set ip 172.30.65.22; commit'
cmsh -c 'device; interfaces node006; use BOOTIF; set ip 172.30.65.23; commit'
```

ディスク限定と対応を確認した台から順に PXE 起動し、各台の結果を記録する。ワーカーの Multus 用 NIC を PXE NIC として登録しない。OS 起動後に追加ディスクが未初期化のまま残っていることを確認し、LVM / TopoLVM 作業は後続で行う。

Kubernetes 等を導入した後は、BCM イメージとの同期や再展開時の除外設定も検討する。`AUTO` や `NOSYNC` という名前だけでローカル変更・データが保持されると判断しない。

## 根拠と適用範囲

- 実機証跡: `input/40-bcm-pxe/2026-09-22-headnode-check.txt`。2026-09-22 JST、採取開始時刻をファイル冒頭に記録。ライセンス識別情報・鍵の内容は採取対象外。`input/` は Git 管理外。
- `input/10-bcm-installer-manual/installation-manual.pdf`: BCM 11、Revision `47eff3c`、2026-09-21。§1.3 pp.10–11（PXE と識別）、第4章 p.57（ヘッドを含む評価ライセンスのノード上限）。[公式公開版](https://docs.nvidia.com/base-command-manager/manuals/11/installation-manual.pdf) でも該当説明を照合した（閲覧時 Revision `4cd22fc`、2026-09-21）。
- `input/10-bcm-installer-manual/admin-manual.pdf`: 同じローカル版。§3.13 pp.166–169（disksetup）、§5.1.1 pp.239–241（PXE）、§5.4.2 pp.264–271（識別）、§5.4.4 pp.276–279（FULL / AUTO 等）、§5.4.6–5.4.7 pp.281–282（ディスク確認・同期）、§5.8.2–5.8.3 pp.313–314（ログ）。ページ番号は PDF 通し番号と紙面番号が一致。
- 実機では `versioninfo` の BCM 11.0 とパッケージ版を記録した。インストーラーの `11.34.0` 表示とは区別する。上記資料の手順は実機のヘルプ・現在値で照合した範囲に適用し、OS 展開成功を示すものではない。
