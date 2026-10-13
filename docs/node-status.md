# 各ノードの状態確認

## 2026-10-14 の読み取り専用調査

実施時刻: 00:48～00:49 JST。実行者: Codex。目的は BCM ヘッドと計算ノード 6 台の現在状態の確認。実行場所は BCM ヘッドの root シェル。既存の管理権限・SSH 公開鍵認証と登録済みホスト鍵、または展開元イメージの公開ホスト鍵を前提とする。ユーザーによる新たな実行報告はない。

製品版: 実機の `main versioninfo` は Cluster Manager 11.0 / CMDaemon 3.1 / Build Index 165270。ノードの OS は [今回の構成確認](environment.md#2026-10-14-の状態確認) を参照。過去に報告された BCM 11.33 の Kubernetes 障害環境と同一であることは未確認。

### 実行順と結果

1. リポジトリで `pwd`、`rg --files`、`git status --short --untracked-files=all` を実行。開始時の変更はなし。README、AGENTS、環境構成、VM 一覧、検証状況、既存 PXE・CIDR 障害・保守記録を `cat` / `sed` / `tail` / `rg` で確認。長い出力は一部省略された。`git log -1 --format='%h %an <%ae>'` で既存の公開用汎用名義を確認した。
2. `command -v cmsh kubectl ssh virsh` と `date -Iseconds` を実行。cmsh と ssh は PATH 上に存在し、kubectl / virsh は見つからなかった。Python `subprocess.run` で以下を採取し、JSON に日時・引数・終了コード・標準出力・標準エラーを保存した。初回の cmsh は終了 1、systemctl は bus への Operation not permitted。これは実行制限の影響を含むため停止判定には使わない。

```bash
cmsh -c 'main versioninfo'
cmsh -c 'device list'
id -u
uptime
systemctl is-active cmd
systemctl --failed --no-pager
free -h
df -h /
command -v kubectl
ls /cm/local/apps/kubernetes/ /root/.kube/
```

3. 実行制限の外で cmsh 2 件とヘッドのサービス照会を再実行。cmsh は双方終了 0、cmd は active。失敗ユニットは shorewall6.service の 1 件。Kubernetes 配置候補と `/root/.kube` の `ls -d` は対象なしで終了 2（標準エラーは抑制）。ヘッドのメモリは 31 GiB 中 3.8 GiB 使用、ルートは 9% 使用、稼働約 21 日。ライセンス・外部疎通・失敗原因は今回調査していない。
4. node001～006 に下記の SSH オプションで並列照会（最大 4 本、SSH 接続 6 秒、プロセス 25 秒の上限）。期待結果は接続成功と OS 状態取得。node001・002 は接続成功。末尾の kubelet 設定存在判定が false のため複合コマンドの終了は 1。node003・004 は未登録ホスト鍵で終了 255、node005・006 は `No route to host` で終了 255。後者だけで VM 電源断とは断定しない。

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=6 -o ConnectionAttempts=1 <NODE> '<確認コマンド>'
```

`<NODE>` は node001～006 に置換。初回の確認コマンドは順に `uptime`、`uname -r`、`systemctl --failed --no-pager`、`systemctl is-active kubelet containerd`、`free -h`、`df -h /`、`swapon --show`、`command -v kubectl`、`test -f /var/lib/kubelet/config.yaml && echo kubelet-config-present`。

5. [既存のホスト鍵照合手順](bcm-pxe-provisioning.md#2026-09-23-node001003-の-bcm-からの一括確認) と同様に、`/cm/images/default-image/etc/ssh/ssh_host_ed25519_key.pub` の公開鍵を読み、node003・004 用の一時 known_hosts を Python `tempfile.mkstemp`（権限 600）で生成した。SSH に `UserKnownHostsFile=<一時ファイル>` を加え、StrictHostKeyChecking=yes を維持して照合・接続に成功。既存 known_hosts は変更せず、一時ファイルは finally で削除した。イメージ共有鍵による照合であり、ノード固有鍵による識別ではない。node001～004 に以下を再照会し、4 台とも終了 0。末尾の `command -v` は `|| true` で不在を許容しており、全項目の存在を意味しない。

```bash
uptime
uname -r
systemctl --failed --no-pager
systemctl show kubelet containerd -p Id -p LoadState -p ActiveState
free -h
df -h /
swapon --show
. /etc/os-release; echo OS=$PRETTY_NAME
if test -f /var/lib/kubelet/config.yaml; then
  echo kubelet-config=present
else
  echo kubelet-config=absent
fi
command -v kubectl || true
```

### 判定範囲と残課題

各台の最新判定は [検証状況](validation.md#2026-10-14-の各ノード実機確認) に集約する。node001～004 は失敗ユニット 0、kubelet.service / containerd.service は LoadState=not-found、標準 kubelet 設定なし、kubectl は PATH 上になかった。Kubernetes の API / Ready / etcd の健全性は未確認。標準配置以外の導入を網羅的に否定する調査ではない。

node005・006 は BCM 上で MAC 未登録・DOWN / unassigned。予定ワーカー IP と異なる初期割り当てが残っている。これは [既存の環境記録](environment.md#ip-アドレス計画) の未展開状態と整合するが、物理ホストの VM 電源・ディスクは今回未照会。ヘッドの shorewall6 の原因・影響は未確認。サービス変更、再起動、展開、ホスト鍵検証の無効化は行っていない。

### 証跡と文書保存

一次資料は Git 管理外の `input/90-node-status/` に保存。`bcm-version.json` / `bcm-devices.json` / `head.json` が初回、`*-retry.json` が権限制限を除いた再試行と初回 SSH、`node001-detail.json`～`node004-detail.json` が追加照会。各 JSON に 2026-10-14 JST の採取日時を記録。チャットのツール出力も根拠とする。

本書・環境構成・検証状況・README を更新後、Markdown の表・コードフェンス・相対リンクと差分を確認する。ステージ済みの name-status / check / 全差分、秘密情報候補、input の非追跡・除外、コミット名義を確認しコミットする。原本、公開鍵本文、ヘッドの実ホスト名は追加しない。今回の公開文書には既存の公開可能な検証ノード名だけを使用し、IP・MAC の実値は転記しない。公開・push・過去履歴全体の監査は対象外。コミット ID と残変更は完了報告に記載する。

保存時の初回 `git add` は `.git/index.lock` を作成できず終了 128（Git 管理領域が読み取り専用）。この試行では後続のステージ確認は未実行。Git 書き込み権限を伴う同操作で再試行する。

再試行のステージは成功し、対象 4 文書の全差分・空白エラーなし・input 非追跡と除外を確認した。Python でコードフェンスの対応と相対リンク先ファイルの存在を確認。既定 Git 名義には実ヘッド名が含まれたため、コミット時だけ既存の公開用汎用名義を明示し、実値をコミット情報に含めない。文書にはヘッド実名・IP・MAC・鍵本文を転記せず、公開情報の未解決事項はない。
