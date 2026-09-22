# リポジトリ保守手順と実施記録

## 2026-09-22: 実行した手順の保存を必須化

### 目的・前提

実行した手順を必ず手順書として保存するという利用者の指示を、[作業方針](../AGENTS.md) に定める。対象は本リポジトリの文書で、製品バージョンに依存しない。編集ツールと Git のバージョンは未記録。

実行場所はリポジトリを配置した作業環境のルートディレクトリ。ファイルの編集とローカル Git コミットが可能な権限を前提とする。VM・クラスタへの操作は伴わない。

### 実行した手順

1. `pwd` と `rg --files -g 'AGENTS.md' -g 'README.md' -g 'docs/**' -g '.gitignore'` で作業場所と文書構成を確認し、`git status --short --untracked-files=all` で開始前の変更がないことを確認した。
2. `AGENTS.md`、`README.md`、`docs/validation.md`、`docs/bcm-pxe-provisioning.md`、`.gitignore` を読み、既存の記録方針・手順書の構成・一次資料の除外設定を確認した。
3. `apply_patch` で `AGENTS.md` に手順書化の必須ルールを追加し、読み取り専用調査の扱いと更新後の確認項目を整合させた。README の資料更新手順にも必須事項とルールへのリンクを追加した。
4. `git var GIT_AUTHOR_IDENT` と `git var GIT_COMMITTER_IDENT` でコミット名義を確認した。内部ホスト名を含むため、公開用の汎用名義を今回のコミットに指定することにした。元の識別情報は本書へ転記しない。
5. `rg -n -i 'password|パスワード' docs/environment.md` で既存のパスワード欄を確認した。実値はなく、`<PASSWORD>` のプレースホルダーだった。
6. 本書を作成し、README の索引へ追加した。

### 保存前の確認・コミット手順

実行場所と権限は上記と同じ。次のコマンドでステージする対象を明示し、ステージ済みの全文・差分を公開基準に沿って確認する。`input/publication-check.txt` は除外設定を確認するための仮のパスで、ファイル作成は不要。

```bash
git status --short --untracked-files=all
git add AGENTS.md README.md docs/repository-maintenance.md
git diff --cached --name-status
git diff --cached --check
git diff --cached
git ls-files -- input
git check-ignore -v -- input/publication-check.txt
```

Markdown の見出し・表・コードブロック・相対リンクを確認する。差分だけでなく変更文書の文脈も読み、認証情報・個人情報・接続情報・第三者資料が追加されていないことを確認する。問題があれば修正・再ステージし、同じ確認を繰り返す。

確認完了後、以下でローカルコミットと残変更の確認を行う。`Repository Maintainer` と `maintainer@example.invalid` は実在の個人・接続先を表さない公開用の名義。コマンド内の環境変数はこのコミットだけに適用し、Git の永続設定は変更しない。

```bash
GIT_AUTHOR_NAME='Repository Maintainer' GIT_AUTHOR_EMAIL='maintainer@example.invalid' GIT_COMMITTER_NAME='Repository Maintainer' GIT_COMMITTER_EMAIL='maintainer@example.invalid' git commit --only AGENTS.md README.md docs/repository-maintenance.md -m 'docs: require documentation of executed procedures'
git status --short
git log -1 --format='%h %s'
```

### 結果・証跡・残課題

期待結果は、実行済み手順の保存義務・保存先・記載項目・保存期限が明文化され、README から参照できること。ルールと索引への反映を確認した。証跡は本作業の Git 差分とコミット履歴。コミット後の ID と残変更の有無は作業完了報告に記載する。

初回の `git add` は作業環境の書き込み制限により `.git/index.lock` を作成できず失敗した。Git 管理領域への書き込み権限を伴う実行で再試行し、ステージに成功した。また、作業途中に `docs/bcm-pxe-provisioning.md`、`docs/environment.md`、`docs/validation.md` の別の変更がステージされたことを検出した。この作業では編集していないため、`git commit --only` で今回の 3 文書だけを指定し、他の変更を取り込まない。コミット直前に対象文書を再ステージし、ステージ済み差分と作業ツリーが一致することも確認する。

過去の実行手順の網羅性確認と実環境の再検証は行っていない。今回のルール追加に伴う環境構成・検証進捗の変更はない。

## 2026-09-23: Codex とユーザー双方の実行記録を明文化

### 目的・前提

[手順書化のルール](../AGENTS.md#実行した手順の手順書化必須) に、Codex とユーザー双方の実行が記録対象であること、およびユーザー実行の記録方法を明記する。実行者は Codex（読み取り専用レビューを委任したサブエージェントを含む）。この作業でユーザーが実行したコマンドの共有はない。

対象は `AGENTS.md` と本書。実行場所はリポジトリのルートディレクトリで、文書編集とローカル Git コミットの権限が必要。Git は 2.43.0、編集ツールのバージョンと操作ごとの時刻は未記録。製品バージョンに依存せず、VM・クラスタの操作は行わない。

### 実行した手順

1. `pwd`、`git status --short --untracked-files=all`、`rg --files -g 'AGENTS.md' -g 'README.md' -g 'docs/**' -g '.gitignore'` で作業場所・文書・開始時の変更を確認した。開始前から `README.md` に未ステージの変更があったため、今回の編集・コミット対象から外した。
2. `cat AGENTS.md`、`cat README.md`、`cat docs/repository-maintenance.md`、`git diff -- README.md`、`cat .gitignore` で既存方針・索引・保守記録・既存差分・除外設定を確認した。実行手順の保存義務はあったが、Codex とユーザー双方を対象とする明記はなかった。サブエージェントにも方針と保守記録の読み取り専用レビューを依頼し、同じ不足を確認した。
3. `git --version`、`date -I`、`git log -1 --format='%h %s'`、`git var GIT_AUTHOR_IDENT`、`git var GIT_COMMITTER_IDENT` でバージョン・実施日・直前のコミット・コミット名義を確認した。既定の名義には公開可否未確認の識別情報があるため、前回と同じ公開用の汎用名義をコミット時に指定する。実値は転記しない。
4. `apply_patch` で `AGENTS.md` と本書を更新した。記録対象・実行者・根拠・結果の項目を明記し、ユーザーから共有された情報の反映方法、情報不足時の扱い、提示しただけのコマンドを未実行とするルールを追加した。
5. `git diff --check`、`git diff --stat`、`git diff -- AGENTS.md docs/repository-maintenance.md` と、前回の確認手順にある status・`input/` の非追跡・除外確認を実行した。空白エラーと原本の混入はなかった。初回の `git add AGENTS.md docs/repository-maintenance.md` は Git 管理領域が読み取り専用のため終了コード 128 で失敗した。再試行には同領域への書き込み権限を伴う実行が必要。
6. `git log -3 --format='%h %s'`、`tail -65 docs/repository-maintenance.md`、`git status --short --untracked-files=all` で、並行作業の README 整理が別コミットとして保存されたことを確認した。本書に加わったその作業記録を保持し、今回の差分は方針の追記と本節だけであることを確認した。
7. Git 管理領域への書き込み権限を伴う実行で同じ `git add` を再試行し、成功した。ステージ済みの対象一覧・差分・空白エラーを前回の手順で確認した。`git grep --cached -n -i -E 'password|token|secret|Authorization|PRIVATE KEY|https?://|@' -- AGENTS.md docs/repository-maintenance.md` と差分・文脈の目視で公開情報を確認し、`git diff --exit-code -- AGENTS.md docs/repository-maintenance.md` でステージ内容と作業ツリーの一致を確認した。`rg -n -i 'password|パスワード' docs/environment.md` で既存のパスワード欄が `<PASSWORD>` であることも確認した。`sed -n` による変更箇所の読み直しで、見出し・リンク先とアンカー・コードブロックの対応を確認した。

### 保存前の確認・コミット手順

[前回の確認手順](#保存前の確認コミット手順) を今回の 2 文書に限定して適用する。確認結果を本節へ反映した後にも、再ステージして同じ公開情報チェックを繰り返す。ステージ対象は `git add AGENTS.md docs/repository-maintenance.md`、コミット対象とメッセージは次のとおり。README の既存索引から本書を参照できるため、索引の追加は不要。

```bash
GIT_AUTHOR_NAME='Repository Maintainer' GIT_AUTHOR_EMAIL='maintainer@example.invalid' GIT_COMMITTER_NAME='Repository Maintainer' GIT_COMMITTER_EMAIL='maintainer@example.invalid' git commit --only AGENTS.md docs/repository-maintenance.md -m 'docs: clarify recording of Codex and user executions'
git status --short
git log -1 --format='%h %s'
```

### 結果・証跡・残課題

期待結果は、双方の実行を保存する義務と記録方法が明文化されること。更新した方針に、実行者と根拠の区別、ユーザー操作を自動収集したと見なさないこと、未共有・未確認の扱いが含まれることを確認した。証跡は今回のツール実行結果、Git 差分・コミット履歴。ツール出力の原本ファイルは未保存。コミット後の ID と残変更は完了報告に記載する。

公開情報チェックはステージ済み 2 文書の差分と関連文脈、ファイル名・コミットメッセージ・公開用の名義、`input/` の非追跡・除外を対象とし、問題はなかった。認証情報・実環境の識別情報・第三者資料の追加はなく、追加の削除・匿名化は不要。今回の変更に未解決事項はない。公開・push は対象外で、過去の履歴全体は再監査していない。

本作業は文書の確認・更新のみで、過去のユーザー操作の網羅性と実環境は再検証していない。環境構成・検証進捗の変更はない。

## 2026-09-23: README のドキュメント索引を用途別に整理

### 目的・前提

ルート直下と `docs/` の全ドキュメントを README から一覧できるようにし、要件・前提条件などの資料、実施順の構築手順、構築に必要な知見の 3 区分へ整理する。対象は README と本書。実行場所はリポジトリのルートで、文書の編集とローカル Git コミットの権限を前提とする。Git 2.43.0、Python 3.12.3 を使用した。製品バージョンには依存しない。

### 実行した手順

1. `pwd`、`git status --short --untracked-files=all`、`rg --files --hidden -g '!.git/**' -g '!input/**'`、`git ls-files` で作業場所・変更状態・対象ファイルを確認した。開始前の変更はなく、Markdown はルート直下 2 文書と `docs/` の 10 文書だった。
2. `cat README.md`、`cat AGENTS.md`、`cat docs/repository-maintenance.md` と `rg -n '^#{1,4} ' docs`、各文書の概要・関連節の読み取りで役割を確認した。PXE 文書の仕組み・swap の節と、バージョン対応の説明を知見の参照先に選んだ。別エージェントも編集せずに文書構成と分類案を確認し、同じ 12 文書と構築順を確認した。
3. `git --version`、`python3 --version` でツールの版を確認した。Python から `git var GIT_AUTHOR_IDENT` と `git var GIT_COMMITTER_IDENT` を読み、実値は表示せず、公開用の汎用名義をコマンド単位で指定する必要があることを確認した。環境文書の認証情報欄は `<PASSWORD>` であり、実値の追加・転記は行っていない。
4. `apply_patch` で README の索引を 3 区分へ変更した。本書としての README と作業方針も一覧に含め、構築順を「BCM インストール → ライセンス登録 → PXE・OS 展開」と番号で示した。知見は既存のバージョン対応文書と PXE・swap の節へリンクし、未作成の後続手順は検証状況へ案内した。
5. `python3` の `pathlib`・`re`・`unicodedata`・`subprocess` を使う一時スクリプトで、`git ls-files '*.md'` の一覧と索引内リンクを照合した。併せて索引の 3 見出し、変更対象 2 文書の相対リンク先・見出しアンカー・コードブロックの対応を確認し、`git diff --check` で差分の空白エラーがないことを確認した。見出し・表・説明の対応と構築順も目視で確認した。
6. 本節に作業を記録した。保存時は上記の「保存前の確認・コミット手順」を今回の 2 文書に適用し、以下のコマンドで対象を限定する。Git 管理領域は作業環境で読み取り専用のため、ステージとコミットは同領域への書き込み権限を伴う実行を用いる。

### 保存時の確認・コミット

```bash
git status --short --untracked-files=all
git add README.md docs/repository-maintenance.md
git diff --cached --name-status
git diff --cached --check
git diff --cached
git grep --cached -n -i -E 'password|token|secret|Authorization|PRIVATE KEY|https?://|@' -- README.md docs/repository-maintenance.md
git ls-files -- input
git check-ignore -v -- input/publication-check.txt
GIT_AUTHOR_NAME='Repository Maintainer' GIT_AUTHOR_EMAIL='maintainer@example.invalid' GIT_COMMITTER_NAME='Repository Maintainer' GIT_COMMITTER_EMAIL='maintainer@example.invalid' git commit -m 'docs: organize README document index by purpose'
git status --short
git log -1 --format='%h %s'
```

### 結果・証跡・残課題

期待結果は全 12 文書の掲載、用途別の 3 区分、構築順と知見への導線がそろうこと。索引の網羅性、変更対象 2 文書の相対リンク 21 件とアンカー、コードブロックの対応、空白エラーがないことを確認した。証跡は今回の Git 差分とコミット履歴で、コミット後の ID・残変更は完了報告に記載する。

公開情報チェックは今回のステージ済み 2 文書の差分・関連文脈、ファイル名、コミットメッセージと汎用名義、`input/` の除外・非追跡を対象とする。新しい実環境の識別情報や認証情報、第三者資料の転載はなく、追加の匿名化は不要。公開・push は本作業の対象ではなく、過去の履歴全体の公開可否は今回再監査していない。

索引整理について残課題はない。既存文書の構築結果と未確認事項を引き継いでおり、製品資料・実環境の再検証は行っていない。環境構成・検証進捗の変更はない。
