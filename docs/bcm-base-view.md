# BCM Base View への接続手順と確認記録

BCM の Web 管理画面 **Base View** を、既存のポート転送とブラウザーの Proxy 設定で開く手順を示す。環境情報は [環境構成](environment.md)、確認済み範囲は [検証状況](validation.md) に集約する。

## 対象と前提

- 対象は BCM 11 のヘッドノード。導入済みパッケージ版は [実測記録](environment.md#2026-09-23-base-view-の確認) を参照。
- 2026-09-23 のユーザー報告では、BCM ヘッドへのポート転送手順とブラウザーの Proxy 設定は整備済み。具体的なコマンド、Proxy 種別・ポート、ブラウザー版、設定日時は未共有・未記録で、Codex が再検証した状態ではない。
- ブラウザーが既存の Proxy 経由でヘッドの TCP 8081 に到達できること、および管理者のログイン情報を保持していることが前提。新しい転送設定やファイアウォール変更は今回実施していない。
- 以下の IP は [公開可能と確認済みの検証用アドレス](environment.md#ネットワーク)。パスワードの実値は保存しない。

## ブラウザーで接続する

実行場所はユーザーのブラウザー。以下は案内した手順であり、今回の画面表示・ログイン成功の報告はまだない。

1. 整備済みのポート転送を有効にし、Proxy を設定したブラウザーで [Base View](https://172.30.64.10:8081/base-view/) を開く。
2. 証明書警告が出る場合は、既存の管理経路で確認できる BCM の証明書と照合し、対象が正しいことを確認して、この検証環境の当該サイトに限って例外を許可する。ブラウザー全体の証明書検証を無効にしない。今回のサーバー側確認では自己署名を含む証明書チェーンを標準の信頼ストアで検証できなかった。ブラウザー側の実際の警告内容は未確認。
3. ログイン画面でユーザー名 `root`、パスワードに **BCM ヘッドノードの root パスワード**を入力する。変更済みなら現在の値を使う。パスワードをチャットへ貼り付ける必要はない。
4. ログイン後にクラスタの概要画面が表示されることを確認する。

URL には HTTPS、ポート `8081`、パス `/base-view/` を含める。タイムアウトの場合は、既存の転送が動作中か、この宛先がブラウザーの Proxy 除外対象になっていないかを確認する。ログイン画面まで表示されるが認証が失敗する場合は、到達性と認証の問題を分けて調べる。今回、認証要求は送信していない。

## 根拠と適用範囲

一次資料は `input/10-bcm-installer-manual/admin-manual.pdf`、NVIDIA Base Command Manager 11 / Revision `47eff3c` / 2026-09-21。以下の本文では紙面番号と PDF 通しページが一致する。

| 項目 | 参照箇所 | 内容 |
|---|---|---|
| URL・提供元 | §2.4.1 pp.38–39 | HTTPS 8081 の `/base-view`。ヘッドの cluster manager が提供し、`base-view` パッケージは標準導入 |
| ログイン | §2.3.1 pp.34–35、§2.3.3 pp.36–37、§6.5 pp.340, 346 | ヘッドの root パスワード、Base View のユーザー名・パスワード認証、root の管理権限 |
| サービス | §2.6–2.6.1 pp.82–83 | Base View は CMDaemon と通信し、管理対象サービスは `cmd.service` |

2026-09-23 に [NVIDIA 公式 Admin Manual 配布先](https://docs.nvidia.com/base-command-manager/manuals/11/admin-manual.pdf) の Web 検索抜粋でも URL とポートを確認した。抜粋のページ表示はローカル版と異なるため、章・ページ番号は上記ローカル版を根拠とする。[NVIDIA の Base View ログイン説明](https://docs.nvidia.com/dgx-superpod/administration-guide-dgx-superpod/latest/cluster-management.html#base-view-login-window) でも root と導入時に設定したパスワードを確認した。後者は DGX SuperPOD 向け資料の補足であり、そのハードウェア構成や画面配置を本環境の実測として扱わない。

## 2026-09-23: 接続先の調査と応答確認

### 目的・実行場所・権限

実行者は Codex（資料調査のサブエージェントを含む）。ユーザーの接続依頼を受け、接続先とサーバー側の配信状態を調べた。BCM ヘッド上のリポジトリルートで実行し、サービス・ソケット照会には作業環境の制限外での読み取り権限を用いた。Git 2.43.0、Python 3.12.3、curl 8.5.0 を確認した。OS の版は既存の [ヘッド確認](environment.md#2026-09-22-の稼働後確認) を引き継ぎ、今回は再照会していない。

### 実行順と結果

1. `pwd`、`git status --short --untracked-files=all`、`rg --files`、`cat`、`rg -n`、`sed -n`、`tail` で方針・README・環境構成・検証状況・製品資料索引・既存の導入／ライセンス／PXE／保守記録と `.gitignore` を確認した。開始前の Git 変更はなかった。`rg --files input` で一次資料の所在を確認した。広い範囲の表示ではツールの出力上限による省略があり、対象文書・必要箇所を分けて読み直した。
2. `date -Iseconds` は 01:14:20 JST、`git --version` と `python3 --version` は上記の版。`command -v cmsh` / `curl` / `ss` でコマンドの存在を確認した。利用可能ツールの一覧からブラウザー関連機能を調べたが、ブラウザーの操作は行っていない。公式 Web 検索・閲覧と、サブエージェントによる次の並行調査（01:14～01:16 JST）で上記の製品仕様を確認した。

   サブエージェントは `pwd`、`rg --files`、`cat`、`rg` で README・製品資料索引・導入／環境／ライセンス記録を確認した。`rg --files --hidden --no-ignore input` に続く `command -v pdftotext` は終了 1（未導入）で、同じ `&&` 列の `date` は未実行。Python の `importlib.util.find_spec` で標準環境に PDF 読み取りライブラリがないことを確認後、`rg --files --hidden --no-ignore /tmp /opt /usr/local/lib /root/.cache` で既存の `/tmp/bcm-pdf-read/pypdf` を見つけた。`PYTHONPATH=/tmp/bcm-pdf-read python` と `PdfReader`（pypdf 6.19.0）で 1094 ページの PDF を読み、表紙・関連ページを `/tmp/baseview-admin-page-<ページ>.txt` へ抽出し、`cat` / `rg` で照合した。抽出・照合に成功し、追加インストール・実環境操作はしていない。
3. 通常の制限下で `systemctl is-active cmd` を試みたが、`Failed to connect to bus: Operation not permitted`、終了コード 1 で停止した。`&&` で後続に置いた待受・IP・パッケージ・curl 版のコマンドはこの試行では未実行。BCM サービスが停止しているという結果ではない。
4. 必要な読み取り権限で、Python の `subprocess.run` から次のコマンドを順に実行した。標準出力・標準エラー・終了コードを `input/70-base-view/2026-09-23-service-check.txt` に保存した。

   ```bash
   systemctl is-active cmd
   ss -ltnp 'sport = :8081'
   ip -4 -brief address show enp2s0
   dpkg-query -W -f='${Package}\t${Version}\n' base-view cmdaemon
   curl --version
   curl --noproxy '*' --connect-timeout 5 --max-time 15 -sS -o /dev/null -w 'HTTP %{http_code}\n' https://172.30.64.10:8081/base-view/
   ```

   最初の 5 コマンドは終了コード 0。`cmd` は active、`*:8081` を cmd が LISTEN、管理 NIC は UP で既存の管理 IP と一致した。パッケージ版は環境構成へ記録した。最後の curl は終了コード 60、HTTP 000、`self-signed certificate in certificate chain` で証明書検証に失敗した。
5. ユーザーから既存の転送手順・ブラウザー Proxy の整備済み報告を受領した。これは設定済みという報告のみで、実施コマンド・画面操作の共有はない。転送を再作成せず、上の URL とログイン方法を案内した。
6. 証明書検証と画面配信を切り分けるため、同じヘッド上で **認証情報を送らない 1 回の GET** に限定して `-k` を付け、01:15:45 JST に応答を確認した。

   ```bash
   curl --noproxy '*' --connect-timeout 5 --max-time 15 -k -sS \
     -o input/70-base-view/2026-09-23-base-view.html \
     -w 'HTTP %{http_code}\nContent-Type %{content_type}\n' \
     https://172.30.64.10:8081/base-view/
   ```

   終了コード 0、HTTP 200、`Content-Type: text/html`。Python で取得 HTML の title を抽出し、`Base View`、1090 bytes を確認した。コマンド・結果・日時は `input/70-base-view/2026-09-23-page-check.txt`、HTML 原本はコマンドの出力先に保存した。`-k` はこの診断要求だけに適用し、恒久設定の変更や認証・ログイン確認はしていない。
7. 本書と README 索引・製品資料の参照箇所・環境構成・検証状況を更新した。保存前に下記の文書・公開情報チェックを行い、同じ作業単位でコミットする。
8. Python で今回の 5 文書の相対リンク 99 件・見出しアンカー・コードブロックの対応を照合し、エラーなし。サブエージェントも `git diff`、新規文書全文の `cat`、環境構成冒頭の `sed -n`、`git diff --check` で資料との整合・公開確認の根拠を独立確認し、指摘なしだった。表・見出しと実測／未確認の区別も目視確認した。
9. 途中の `git status` で別作業の PXE・環境構成・検証状況のステージ済み変更を検出した。`git diff --cached --stat`、対象差分、`git log -2` を確認した時点では別作業が `beff325` に保存済みで、ステージは空だった。その後の status と環境構成・検証状況の差分で、本作業の 5 文書だけが残っていることを確認した。別作業の変更やステージは操作していない。

### 文書確認と保存

[リポジトリの保存前確認手順](repository-maintenance.md#保存前の確認コミット手順) を今回の `README.md`、`docs/bcm-base-view.md`、`docs/references.md`、`docs/environment.md`、`docs/validation.md` に限定して適用する。相対リンク・見出し・表・コードブロックを確認し、ステージ後の `git diff --cached --name-status` / `--check` / 全差分と関連文脈を読む。`git grep --cached` による認証情報・URL 等の補助検索、`git ls-files -- input` と `git check-ignore -v -- input/70-base-view/2026-09-23-service-check.txt` による原本の除外・非追跡を確認する。コミットには同手順の公開用名義を使い、コミット後に `git status --short` を確認する。

使用するコミットメッセージは `docs: document Base View access and server checks`。Git 管理領域への書き込み権限を伴う実行で、上記 5 文書だけを `git add` する。`git diff --exit-code --` で対象の作業ツリーとステージ内容の一致を確認する。

実施結果: ステージ済みの対象は上記 5 文書のみで、全差分（新規文書は全文）と関連文脈を確認した。差分の空白検査と作業ツリーとの一致は終了コード 0。認証情報・URL 等の補助検索では公開用 IP・公式 URL・既存の `<PASSWORD>` 等のみで、認証情報の実値や第三者原本の追加はなかった。`input/` は非追跡で、今回の原本 3 ファイルは `/input/` による除外を確認した。`git var GIT_AUTHOR_IDENT` / `GIT_COMMITTER_IDENT` も公開用名義をコマンド単位で指定して確認した。ファイル名・コミットメッセージを含め公開情報の問題はなく、追加の削除・匿名化は不要だった。この結果追記後にも再ステージして同じ確認を行う。

### 結果・証跡・残課題

サーバーの待受と Base View の HTML 配信は確認できた。これはヘッドから自身の管理 IP への確認であり、ユーザーの Proxy 経路、ブラウザー上の描画・JavaScript 実行、証明書の信頼、認証成功を証明するものではない。これらはユーザーのブラウザーでの確認が残る。サービス再起動・設定変更・パスワード取得は行っていない。

証跡は上記 `input/70-base-view/` の 3 ファイル、本タスクのツール出力・ユーザー報告、Git 差分・履歴。ローカル資料の抽出物は `/tmp/` に保存し、製品本文・HTML 原本・ログはコミットしない。公開可能な検証 IP と公開製品情報のみを文書へ記載し、秘密情報や未確認のホスト名・Proxy 接続情報は追記しない。公開・push と履歴全体の監査は今回の対象外。コミット ID・公開情報チェック結果・残変更は完了報告に示す。
