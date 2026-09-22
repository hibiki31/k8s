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
