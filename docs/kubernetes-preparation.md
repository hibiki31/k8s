# Kubernetes 導入前の準備と実施記録

実施日: 2026-10-14（JST）。実行者は、明記したユーザー操作・報告を除き Codex。対象は BCM ヘッドと node001～node006。ユーザーの訂正により、今回の範囲は **Kubernetes のインストール手前まで**とし、Kubernetes・etcd・CNI の導入は実行しない。

node004 の運用用ディスクレイアウトへの切替と、通常の AUTO 再起動後の LVM 保持を確認した。node005・006 は VM のディスク対応の確認と初回展開が残る。ユーザーは今回の OS-only FULL 再展開試験を省略し、通常再起動の確認までと指定したため、FULL 後の保持は未検証である。構成の正本は [環境構成](environment.md)、進捗の正本は [検証状況](validation.md) を参照する。

## 前提・権限・証跡

- BCM 11.0 / CMDaemon 3.1（Build Index 165270）を使用する検証環境。`cm-setup` の実測パッケージ版は `11.0-124257-cm11.0-7f8393643d`。BCM のバージョン表記は [既存の整理](bcm-kubernetes-versions.md) と区別する。
- node001～004 のカーネル実測は `6.8.0-106-generic`。Ubuntu 24.04.4 という OS 版は [以前の確認](node-status.md) から引き継ぎ、今回の preflight では `/etc/os-release` を再取得していない。node004 は最後の 01:06:44 の照会でも Ubuntu 24.04.4 を確認した。
- BCM の root 権限、対象ノードの root SSH 権限を使用。物理ホストの管理接続は別途確認が必要。
- 9 月の初回展開・XML の構造検証は [ワーカーの初回展開手順](worker-storage.md) の実施記録を引き継ぐ。記録を埋めるためだけの再実行はしない。
- 一次資料は Git 管理外の `input/80-preinstall/` に保存。コマンド結果 JSON は 0600 とし、認証情報・実ホスト識別情報・UUID・ハッシュ等の原本を公開文書へ転載しない。`input/` の補助スクリプトは clone 後に存在するとは限らない。
- 以下の `<KNOWN_HOSTS>`、`<PHYSICAL_HOST>`、`<PHYSICAL_USER>` はプレースホルダー。実際の接続情報に置換する。lab 用ノード名・IP は既存の公開許可範囲だけを記載する。

## 1. 資料・既存状態を読み取る

作業開始時に `README.md`、`AGENTS.md`、要件・環境・検証状況・ワーカー手順を読み、`git status --short --untracked-files=all` で開始時の作業ツリーがクリーンであることを確認した。以前の Kubernetes / etcd の別件調査記録だけを根拠に、この検証クラスタが導入済みとは判断しなかった。

実際の読み取りでは存在しない `docs/worker-node-provisioning.md` の指定が失敗した。正しい既存手順は `docs/worker-storage.md` であり、その文書を参照した。ツール一覧の発見と、Codex の別チャットの閲覧方法を調べるための `openai-docs` スキルの読取りも実施した。

初回の sandbox 内照会では cmsh が API に接続できず、systemctl は bus、ip は netlink の権限制限で失敗した。実行制限を外した同じ読み取り照会は成功し、BCM の停止とは判定しなかった。`main versioninfo`、`systemctl --failed`、IP / 経路、SSH 設定の有無と libvirt socket の不在も確認した。存在しない setup の `defaults.py` を指定した検索は失敗し、実在する config・実装を参照した。

**BCM ヘッド上**で次の要点を確認した。実行順と各終了コードは `input/80-preinstall/node-preflight.py`（当初の名前は `inspect.py`）および JSON 原本に残した。

```bash
cmsh -c 'device list'
cmsh -c 'category use default; get softwareimage; get initializescript; get finalizescript; get installmode; get newnodeinstallmode'
cmsh -c 'configurationoverlay list'
cmsh -c 'device use node004; get disksetup; get datanode; get installmode; get nextinstallmode; get blockdevicesclearedonnextboot; get initializescript; get finalizescript'
```

同じ device 設定の読取りを node005・006 にも実施した。期待結果は、対象・ディスク・初期化予約・継承元を区別できること。00:54:36～00:54:39 の実測は次のとおり。

| 対象 | 実際の結果 |
|---|---|
| node001～004 | BCM `UP` |
| node005・006 | `DOWN, unassigned`。MAC 未登録。初期の IP 割当のままでワーカー用への変更は未実施 |
| `default` カテゴリ | `default-image`、installmode `AUTO`、newnodeinstallmode `FULL`。初期化・終了スクリプトは空 |
| node004 | 初回用の `/dev/vda` + `/dev/vdb` + VG 定義が保存されたまま。`datanode=yes`、`AUTO`、nextinstallmode・消去予約・初期化/終了スクリプトは空 |
| node005・006 | カテゴリの OS 用ディスク定義を継承。`datanode=no`、個別モード指定なし |
| configuration overlay | 一覧は空 |

証跡: `input/80-preinstall/{workers-settings,category,bcm-list,overlays}.json`。

## 2. node001～004 の OS・通信を確認する

SSH は展開元イメージの ED25519 公開ホスト鍵を一時 known_hosts に登録し、次のオプションで検証した。既存 known_hosts は書き換えず、一時ファイルは接続後に削除した。この鍵はイメージ由来の共有鍵で、ノードごとの固有性を保証するものではない。

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o HostKeyAlgorithms=ssh-ed25519 \
  -o UserKnownHostsFile=<KNOWN_HOSTS> \
  -o GlobalKnownHostsFile=/dev/null -o UpdateHostKeys=no \
  -o ConnectTimeout=8 root@node004
```

**対象ノード内**で確認したコマンドの要点:

```bash
hostname
date -Is
uname -r
nproc
free -h
ip -br addr
ip route
findmnt -no SOURCE,FSTYPE /
lsblk -b -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,SERIAL
swapon --show
systemctl --failed --no-pager
systemctl is-active cmd
timedatectl show -p NTPSynchronized
pvs --reportformat json --units b --nosuffix -o pv_name,pv_uuid,vg_name,pv_size,pv_free
vgs --reportformat json --units b --nosuffix -o vg_name,vg_uuid,vg_size,vg_free,vg_extent_size,pv_count,lv_count
lvs --reportformat json --units b --nosuffix -o vg_name,lv_name,lv_uuid,lv_size,lv_attr,devices
getent ahostsv4 docs.nvidia.com
curl -4 --connect-timeout 5 --max-time 15 -sS -o /dev/null -w '%{http_code}' https://docs.nvidia.com/
```

加えて `/etc/kubernetes`、`/var/lib/kubelet/config.yaml`、`/etc/etcd`、`/cm/local/apps/kubernetes` の存在を確認した。00:54:40 頃の結果:

| 確認 | node001～003 | node004 |
|---|---|---|
| SSH | 全台成功 | 成功 |
| CPU / メモリ表示 | 4 CPU / 15 GiB | 8 CPU / 31 GiB |
| ルート | `/dev/vda3`、XFS | `/dev/vda3`、XFS |
| 仮想ディスク | 128 GiB × 1 | 256 GiB × 2 |
| LVM | PV / VG / LV 一覧は空 | `/dev/vdb1` に `vg_topolvm`、4 MiB の `bcm_seed` 1 個 |
| swap | 16 GiB 有効、使用 0 | 同左 |
| failed unit / cmd | 0 件 / active | 同左 |
| NTP 同期 | 全台 yes | yes |
| IPv4 HTTPS | 全台 HTTP 200 | HTTP 200 |
| Kubernetes 関連の上記パス | 全台存在なし | 存在なし |

node004 の seed はファイルシステム・マウント先なし。VG は PV 1 個、PE 4 MiB、空き `274869518336` bytes（約 255.99 GiB）。追加 NIC は存在するが OS 上で DOWN・IP なしだった。swap は今回変更していない。Kubernetes 導入時の扱いは [既存手順](bcm-pxe-provisioning.md#kubernetes-と-swap) に従い、導入後・再起動後に改めて検証する。

これらのパスがないことと overlay が空であることは、今回の対象で Kubernetes の導入を確認できなかった根拠である。別環境についてユーザーが共有した障害・復旧報告とは区別する。

証跡: `input/80-preinstall/node001-preflight.json`～`node004-preflight.json`。補助スクリプトは `inspect.py`（後述の名前衝突を解消するため `node-preflight.py` に改名）、`manage.py`。

### DNS 初回失敗の追加確認

最初の `getent ahostsv4` は node001～003 で終了コード 2、node004 で 0。その直後の curl は全台 200 だったため、初回だけで DNS 正常とは確定せず追加調査した。

00:57:40～00:57:41 に head・node001～003 で `getent` を各 2 回実行し、すべて 0。Proxy 値を出力せず、関連環境変数が未設定であることだけを確認した上で、次を実行した。

```bash
cat /etc/resolv.conf
curl --noproxy '*' -4 -sS -o /dev/null -w '%{http_code}' \
  --connect-timeout 5 --max-time 15 https://docs.nvidia.com/
systemctl is-active systemd-resolved named bind9
dig +time=3 +tries=1 @172.30.65.1 docs.nvidia.com A
dig +time=3 +tries=1 @172.30.65.1 docs.nvidia.com AAAA
```

直接 IPv4 HTTPS は全台 200。CP の resolver は head を参照し、systemd-resolved は active。head への DNS 問い合わせは A・AAAA とも NOERROR、A はアドレスを返した。初回失敗は再現せず、Proxy 起因の裏付けは得られなかった。

head の named ログには 00:54:41 に外部 IPv6 DNS 宛ての `network unreachable` が複数あった。IPv6 default route がないことは確認したが、最初の `getent` 失敗との因果関係は未確定。DNS の設定変更・サービス再起動は実施していない。

証跡: `input/80-preinstall/dns-{head,node001,node002,node003}-baseline.json`、`dns-head-shorewall6-followup-2.json`。

### head の shorewall6 失敗を確認する

00:58:10～00:58:26 に `systemctl status/show/cat shorewall6`、当該 unit と named の journal、`ip -6 route`、IPv4 forwarding の sysctl、IPv4 shorewall の active 状態、IPv6 の interfaces / zones / 設定ファイルを読み取った。

shorewall6 は 9 月 22 日の起動時から失敗し、`No network interfaces defined`、終了コード 255。interfaces に有効な定義行がなかった。一方、IPv4 shorewall は active、`net.ipv4.ip_forward=1`、CP 3 台からの IPv4 HTTPS は成功しており、今回の IPv4 通信への阻害は観測しなかった。shorewall6 の無効化・設定変更は行っていない。

証跡: `input/80-preinstall/dns-head-shorewall6-0.json`～`-6.json`、`dns-head-shorewall6-followup-0.json`～`-2.json`。

## 3. node004 を運用用 XML に切り替え、保持を試験する

対象は node004 のみ。事前の LVM 一覧は seed だけであり、Kubernetes 関連パスは存在しなかった。00:55:37 に OS 上のファイル一覧と `df -h /` を読み取ったが、ファイル名の確認だけで全データが不要とは判断しなかった。ファイル内容や秘密鍵はこの確認では取得していない。

### 3.1 運用用レイアウトを検証する

既存の `input/70-worker-lvm/node004-os-only.xml` は OS `/dev/vda` の定義を維持し、追加ディスク・VG 定義を含めない。構成方針と初回の静的検証は [既存手順](worker-storage.md#初回作成後のデータ保持) を参照。

00:55:38 に BCM ヘッドで次を実行し `All good` を確認した。

```bash
cmsh -c 'device use node004; set disksetup /root/k8s/input/70-worker-lvm/node004-os-only.xml; validate; get disksetup; get datanode; get installmode; get nextinstallmode; get blockdevicesclearedonnextboot'
```

直前に Python ElementTree で初回用と運用用の OS 定義一致・運用用が vda だけであることを確認し、xmllint の XSD 検証も終了 0。上記 cmsh の `All good` は stderr に出たが、補助処理が stdout を検査していたため AssertionError で停止した。この呼出しには commit がなく、終了時に未保存変更の警告が出た。後続の再読でも初回用 XML が返ったため、検証結果を保存済みとは扱わなかった。

### 3.2 新しい試験 LV を作る

00:56:29 に node004 で、同名 LV が存在しないことを前提に `bcm_persist_test` を新規作成し、作成成功後だけ全 16 MiB に試験データを書き込んだ。対象を誤るとデータを上書きするため、既存 LV にそのまま再実行しない。

```bash
lvcreate -L 16M -n bcm_persist_test vg_topolvm
dd if=/dev/urandom of=/dev/vg_topolvm/bcm_persist_test \
  bs=1M count=16 iflag=fullblock conv=fsync
```

LV 作成成功、書込 `16777216` bytes、終了コード 0。00:56:31 に `pvs` / `vgs` / `lvs` で PV・VG・LV の UUID、サイズ、個数、配置を取得し、`blockdev --getsize64` で LV 全長を確認後、`sha256sum /dev/vg_topolvm/bcm_persist_test` を保存した。UUID とハッシュの実値は公開しない。

比較用のコマンドは `input/80-preinstall/lvm-snapshot.sh` に記録。これは LVM の snapshot LV を作る操作ではなく、メタデータと試験 LV のチェックサムを取得する読み取り処理である。

### 3.3 保存と再読を終えてから AUTO 再起動する

00:56:32 の DB 再読で初回用 XML が残ることを検出し、再起動前の assertion で停止した。stderr の検証成功表示を確認し、00:56:48 に明示的に commit した。

```bash
cmsh -c 'device use node004; set disksetup /root/k8s/input/70-worker-lvm/node004-os-only.xml; commit'
cmsh -c 'device use node004; get disksetup'
cmsh -c 'device use node004; get disksetup; get datanode; get installmode; get nextinstallmode; get blockdevicesclearedonnextboot; get initializescript; get finalizescript'
```

00:56:49 と 00:57:37 の再読で `/dev/vda` のみ、VG 定義なし、`datanode=yes`、`installmode=AUTO`、nextinstallmode・消去予約・初期化/終了スクリプトは空と確認。VG と seed の実体を削除する変更ではない。

00:57:38 に node004 で `systemctl reboot` を実行した。以後は BCM の状態、installer interaction、synclog、SSH とルートファイルシステムを照合した。

```bash
cmsh -c 'device status node004; device installerinteractions -n node004'
cmsh -c 'device synclog node004'
```

00:58:15 の初回照会では `device status` の後に `installerinteractions` のみを指定し、`Command not found`、終了コード 1 となった。以後は `device installerinteractions` と完全なコマンドを指定し成功した。

再起動中も SSH に応答する局面があった。00:59:12 の root は `172.30.65.1:/cm/node-installer` の NFS であり、systemctl は chroot 内として処理を無視した。この時点の SSH 成功や LVM 可視性を、通常 OS の起動完了とは扱わず待機した。

### 3.4 通常 OS の起動後に比較する

BCM の新しい synclog は 00:58:59 に **SYNC** 開始、00:59:18 に Rsync 完了を記録。00:59:56 以降に `UP`、確認待ちなしとなった。初回に読んだ synclog は 9 月 23 日の旧 FULL 記録だったため、日時を比較して今回の結果から分離した。

01:00:20 の最終確認では通常 OS の `/dev/vda3` 起動、cmd active、failed unit 0 件を確認した。起動前と同じ LVM メタデータ・試験 LV 全体の SHA-256 を比較し、以下が一致した。

- PV・VG・seed / 試験 LV の UUID、容量、LV 配置。
- VG の PE サイズ・PV 数 1・LV 数 2、試験 LV を含めた空き容量。
- 試験 LV 全 16 MiB の SHA-256。

VG / LV は自動で active となり、手動 `vgchange -ay` は不要だった。**OS-only レイアウトに切り替えた通常の AUTO → SYNC 再起動で、追加ディスクの VG と LV 内容を保持できた**ことを確認した。

証跡: `input/80-preinstall/node004-os-only-{validate,commit,readback}.json`、`node004-create-test-lv.json`、`node004-before-auto.json`、`node004-before-auto-bcm{,-retry}.json`、`node004-auto-reboot.json`、`node004-auto-progress.json`、`node004-after-auto.json`、`node004-auto-os-proof.json`、`node004-auto-state-final.json`、`node004-auto-status-0100.json`、`node004-auto-sync-0100.json`、`node004-auto-state-0101.json`、`node004-auto-finished.json`。中間証跡のファイル名だけで起動完了を判定せず、実出力を参照する。

### 3.5 FULL 試験の省略と後片付け

AUTO 試験後、OS-only FULL の保持試験と事前バックアップを準備した。最初の実行要求は自動承認レビューにより実行前に拒否された。レビューは、直近の別チャットへの操作許可が情報照会・電源操作に限定される点と、`/etc`・`/root`・`/home` の広範な取得には秘密鍵等が含まれる点を理由として示した。バックアップだけの再試行も実行前に拒否された。

ユーザーへ理由を伝えて確認したところ、「今回は省略し、通常再起動の確認までにする」と回答した。そのため **今回の FULL 試験とバックアップは省略で確定**し、承認待ちの作業として残さない。準備したスクリプトは実行済み証跡ではなく、バックアップファイルの作成、FULL 予約、FULL 用再起動は実施していない。

01:04:48 に試験データの同一性を再確認し、01:04:50 に今回作成した `bcm_persist_test` だけを `lvremove` で削除した。終了コード 0、PV 1 / LV 1、`bcm_seed` 4 MiB の構成へ戻り、VG の空き `274869518336` bytes が回復した。01:04:52 の BCM 再読でも OS-only、`datanode=yes` / `AUTO`、nextinstallmode・消去予約は空と確認した。

01:06:44～01:06:46 に通常 OS・予定 IP / 経路・NTP・cmd・失敗サービス 0・DNS・Proxy を使わない HTTPS 200・seed のみの LVM を再確認した。BCM は node001～004 が UP、node005・006 は未登録のまま、保留中の installer interaction はなし。証跡は `input/80-preinstall/node004-final-health.json` と `bcm-final-devices.json`。

証跡: `input/80-preinstall/node004-test-before-cleanup.json`、`node004-test-cleanup.json`、`node004-final-settings.json`。FULL 後の保持は未検証であり、今回の成功を FULL に拡張しない。

## 4. node005・006 の物理ホスト側の前提を確認する

物理ホストへの既存 SSH 接続経路を読み取り調査した。`ssh -G` で既定のホスト鍵確認が無効だったため、接続試行では必ず `StrictHostKeyChecking=yes` を明示した。

```bash
ssh-keygen -F <PHYSICAL_HOST>
ssh -G <PHYSICAL_USER>@<PHYSICAL_HOST>
ssh-add -l
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=8 -o UpdateHostKeys=no \
  <PHYSICAL_USER>@<PHYSICAL_HOST> true
```

root / system の known_hosts 計 4 候補を確認し、対象の既知鍵は未登録。SSH 応答はあったがホスト鍵検証で終了コード 255 となった。SSH agent は環境変数が残る一方、ソケットが存在しなかった。sandbox 内の `ssh-add -l` は `Operation not permitted`、許可された読み取り再試行では `No such file or directory` と確認。鍵の無条件受け入れ、信頼設定変更、VM 操作は行っていない。

ユーザーは別の物理ホスト管理チャットへ依頼する範囲を、**情報照会と ON / OFF** に限定した。接続設定の変更は依頼しない。Codex アプリの `list_projects`・`list_threads`・`read_thread` で既存会話を閲覧した。`list_threads` の limit 60 は上限を超えて失敗し、50 に訂正して成功した。利用可能な機能には別チャットへの送信がなく、Codex がそこへ依頼を送ったとは扱わない。

本日の別チャットの記録から worker2・3 が停止中で、既存の 2 NIC があることを確認した。ただし、この BCM から `virsh` を実行した結果ではない。ディスクの target・用途・容量・初期化可否の照合は未完了であり、node005・006 の MAC 登録や初回 FULL へ進む前に必要となる。

既存の [ワーカー手順](worker-storage.md#1-物理ホストでディスクと-nic-を確定する) に従い、物理ホスト上の `domstate`、`domiflist --inactive`、`domblklist --inactive --details`、`dumpxml --inactive`、各対象の `domblkinfo` により用途を確認する。これは未実行の次工程である。初回 FULL は XML で指定した OS / 追加ディスクを初期化するため、容量だけでディスクを識別しない。

証跡: `input/80-preinstall/2026-10-14-host-access-check.json`、本日のユーザー指示と Codex アプリの読取り結果。別チャット ID、物理ホストの実名・ユーザー名・鍵情報は掲載しない。

## 5. ライセンスと Kubernetes セットアップの入口を確認する

BCM ヘッドで `verify-license verify` と `cmsh -c 'main licenseinfo'` を実行し、ともに終了コード 0。ライセンス表示は使用 5 / 上限 10 ノード。ライセンス識別情報・証明書等は公開文書へ転記しない。

01:03:24 以降、以下を実行した。これは導入可能版・CLI の確認であり、Kubernetes 導入の実行ではない。

```bash
dpkg-query -W -f='${Package}\t${Version}\n' cm-setup
cm-kubernetes-setup --help
cm-kubernetes-setup --list-versions
```

初回はヘルプ・版一覧とも終了コード 1。補助スクリプトを読み込むための `PYTHONPATH` を子プロセスへ継承した結果、作業用 `inspect.py` が Python 標準の同名モジュールに優先して読み込まれ、既存の証跡ファイルを排他的作成しようとして `FileExistsError` になった。各失敗の途中で先頭の BCM 設定読取りが動いたが、設定変更・証跡の上書きはなかった。製品の不具合や導入処理失敗とは区別する。

補助スクリプトを `node-preflight.py` に改名し、子プロセスの `PYTHONPATH` を除去して再試行した。

```bash
env -u PYTHONPATH cm-kubernetes-setup --help
env -u PYTHONPATH cm-kubernetes-setup --list-versions
```

01:05:29 / 01:05:33 の再試行はともに終了コード 0。版一覧・認定表示の実測と資料との差は [BCM / Kubernetes バージョン対応](bcm-kubernetes-versions.md) に集約する。導入可能版の表示は、Kubernetes のインストール成功を意味しない。

併せて、インストール済み `cmsetup/plugins/kubernetes/` 配下の `plugin.py`、`stages/stages.py`、`network.py`、`roles.py`、`install.py`、`consts.py`、`config.yaml` を読み取り、swap 無効化、カーネルモジュール、sysctl、containerd の設定が BCM セットアップ工程に含まれることを確認した。これらは今回は変更しない。導入後と再起動後の swap 空表示等の実機確認は後続工程に残す。

証跡: `input/80-preinstall/license-{check,info}.json`、`cm-setup-version.json`、`kubernetes-setup-help.json`、`kubernetes-available-versions.json`、`kubernetes-setup-help-cleanenv.json`、`kubernetes-versions-cleanenv.json`。実装調査は当該ファイルの読取り結果に基づく。

## 今回の限界と次工程

- node001～004 の OS / 通信と node004 の通常再起動後の LVM 保持を確認した範囲である。6 台すべての Kubernetes 導入前準備完了とは扱わない。
- node005・006 のディスク用途確認、BCM 設定、初回展開、OS / VG / LV 確認が残る。電源操作だけではディスク構成を確定できない。
- node004 の OS-only FULL 再展開後の保持は今回省略した。実施する場合は影響と保全方法を別途確認する。
- swap の無効化、Kubernetes の役割・採用版・Pod / Service CIDR・API endpoint・CNI の確定と導入は後続工程。今回 Kubernetes や etcd の初期化は行っていない。
- 初回の DNS 失敗と未設定 shorewall6 は上記の観測結果を記録し、変更しなかった。DNS が再び失敗する場合は head の外部 DNS 到達性から切り分ける。

## 文書保存と公開情報チェック

同じテーマの既存手順には最新結果へのリンクを追加し、README・環境構成・検証状況・実機の導入候補を更新した。サブエージェントの資料・実装読取りと実環境照会も本書へ反映した。文書作成には Python とテキスト編集、確認には `cat` / `sed` / `rg` / Git 差分を使用した。実行済みと候補スクリプト、最初の失敗と修正後の結果を分離した。

リポジトリの保守手順に従い、今回の 6 文書だけをステージする。`git status --short --untracked-files=all`、ステージ済み name-status / check / 全差分を確認し、新規文書は全文を読む。Markdown のコードフェンス・相対リンクと参照先アンカー、数値・状態の整合を確認する。input が非追跡・除外対象であること、機微値・原本の混入がないことも確認する。既存パスワード欄はプレースホルダーのまま。コミットには公開用の汎用名義を使用し、実物理ホスト・ヘッドの名前や個人情報を含めない。push・初回公開・過去履歴全体の監査は今回対象外。

作業ツリーとステージ済み 6 文書を確認し、空白エラーなし、新規文書の全文・変更差分に公開不可の実値なしと判定した。相対リンク・見出しアンカー 174 件とコードフェンスは全件正常。input の追跡ファイルは 0、原本・未実行の候補スクリプトは除外対象のまま。実ヘッド名・物理ホスト接続情報・UUID・ハッシュ等は原本にのみ保持し、手順の接続情報はプレースホルダー化した。公開情報の未解決事項はない。この追記を再ステージ・再確認後、汎用名義でローカルコミットし、終了時の ID と残変更を報告する。
