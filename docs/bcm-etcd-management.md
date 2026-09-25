# `cm-etcd-manage` が見つからない場合の調査

調査日: 2026-09-25（JST）

## 結論

`cm-etcd-manage` が別名のコマンドへ置き換えられたことを示す公式情報は確認できなかった。反対に、BCM 11 のリリースノートはこのツールを新機能として明記し、BCM 11.34.0 のリリースノートも `cm-etcd-manage` の修正を記載している。したがって、**BCM 11.34.0 時点でも現行のツール**と判断する。

別環境で裸の `cm-etcd-manage` が `command not found` になる場合、最初に疑うのは改名ではなく次の差である。

1. 実体は `/cm/local/apps/cmd/scripts/cm-etcd-manage` にあるが、このディレクトリが `PATH` に含まれていない。
2. BCM 10 など、ツールが標準パッケージに同梱されない構成または版である。
3. BCM 11 でも `cmdaemon` パッケージの版・更新状態が異なる、またはパッケージ内容が欠けている。

本検証環境の BCM 11 ヘッドノードでも 1 に該当した。`command -v` と `type -a` では見つからなかったが、実体は上記パスに存在し、Ubuntu の `dpkg-query -S` では `cmdaemon` パッケージのファイルだった。`/cm/local/apps/cmd/scripts` は `PATH` に含まれておらず、システムおよび root のプロファイルにもこのコマンドの alias は確認できなかった。絶対パスでの `--help` は、`status`、メンバーの追加・削除、learner の追加・昇格、leader の移動、バックアップ、リストアを表示した。

`cm-kubeadm-manage` は Kubernetes コンポーネントと証明書を扱う別の補助ツールで、`cm-etcd-manage` の後継名ではない。`etcdctl` は状態確認や etcd 自体の低水準操作に使われるが、BCM の設定オーバーレイと etcd メンバーを合わせて扱う `cm-etcd-manage` の単純な置き換えとは扱わない。

## 公式資料から確認した版ごとの扱い

| 対象 | 確認結果 | 判断 |
|---|---|---|
| BCM 11 | [BCM 11 Release Notes](https://docs.nvidia.com/base-command-manager/bcm-11-release-notes/overview.html) は `cm-etcd-manage` を、メンバーの追加・削除、leader 操作、バックアップ・リストアを行う新ツールとして記載 | BCM 11 で導入された正式名称であり、改名の記録ではない |
| BCM 11.34.0 | [11.34.0 Release Notes](https://docs.nvidia.com/base-command-manager/bcm-11-release-notes/bcm11-34-0.html) は、壊れた etcd role 構成の修復と、先頭メンバー停止時のバックアップに関する同ツールの修正を記載 | 2026-09-11 リリースでも保守対象。廃止・置換されたとは読めない |
| BCM 10 以降を対象とする DGX 更新手順 | [Kubernetes Updates](https://docs.nvidia.com/dgx-superpod/update-guide/latest/kubernetes-updates.html) は、スクリプトを `/cm/local/apps/cmd/scripts/cm-etcd-manage` に取得し、実行権限と shell alias を設定する手順を掲載 | BCM 10 系では、裸のコマンドが最初から存在するとは限らない。手動取得は適用版と NVIDIA の案内を確認してから行う |
| BCM 11 Containerization Manual | `input/10-bcm-installer-manual/containerization-manual.pdf`（BCM 11、Revision `47eff3c`、2026-09-21）全 218 ページを検索。`cm-etcd-manage` の記載はなく、`cm-etcd` パッケージ、`cmsh` の `etcd` mode、`EtcdHost` role、`etcdctl` を確認 | マニュアルにコマンドが載っていないことは、廃止の根拠にならない。役割設定・パッケージ・運用ツールを区別する |

手元の BCM 11 製品 PDF 9 冊も横断検索したが、`cm-etcd-manage` / `etcd-manage` の文字列はなかった。Administrator Manual には `cmsh` の `etcd` mode、Containerization Manual には上表の etcd 関連説明がある。公開リリースノートとインストール済みパッケージの実体を優先して、ツールの存否を判断した。

## 別環境で最初に行う読み取り確認

次のコマンドは **BCM ヘッドノードの root shell** で実行する。etcd のメンバー変更・バックアップ・リストアは行わず、版、ファイル、パッケージ所有関係だけを確認する。以下は今回の別環境では未実行の確認例である。

```bash
# 1. shell からの検索と、BCM の標準的な配置先を分けて確認する
type -a cm-etcd-manage || true
command -v cm-etcd-manage || true
test -x /cm/local/apps/cmd/scripts/cm-etcd-manage \
  && ls -l /cm/local/apps/cmd/scripts/cm-etcd-manage

# 2. BCM の版を確認する。CMDaemon が利用できない場合は失敗し得る
cmsh -c 'main versioninfo'

# 3a. Ubuntu / Debian 系: パッケージの版とファイル所有者
dpkg-query -W -f='${Package}\t${Version}\t${Status}\n' cmdaemon cm-setup
dpkg-query -S /cm/local/apps/cmd/scripts/cm-etcd-manage

# 3b. RPM 系: 上記 3a の代わりに使用する
rpm -q cmdaemon cm-setup
rpm -qf /cm/local/apps/cmd/scripts/cm-etcd-manage

# 4. ファイルが存在する場合だけ、絶対パスでヘルプを確認する
/cm/local/apps/cmd/scripts/cm-etcd-manage --help
```

確認結果は次のように判断する。

| 結果 | 判断と次の対応 |
|---|---|
| ファイルあり、裸のコマンドだけ失敗 | `PATH` / alias の問題。絶対パスで実行するか、公式 DGX 手順と同様に現在の shell だけへ alias を設定する。恒久的な symlink やプロファイル変更は、環境の運用基準に従って別途判断する |
| BCM 11、ファイルなし | `cmdaemon` の版・ファイル一覧・更新状態を正常な同版環境と比較する。改名と推測せず、BCM の対応する更新を適用するか NVIDIA サポートへ確認する |
| BCM 10、ファイルなし | 公式 DGX 更新手順は NVIDIA 配布元からスクリプトを取得する方式を案内している。既存ファイルを上書きし得るため、対象 BCM リリースへの適用可否と入手物を確認してから導入する |
| ファイルあり、絶対パスでも失敗 | 実行権限、所有者、shebang の interpreter、依存 Python module、`cmdaemon` の状態、対象 Kubernetes cluster 名と etcd module を順に確認する。これは `command not found` とは別の障害である |

ファイルがある場合の一時的な呼び出し例は次のとおり。alias はその shell にだけ有効であり、これ自体は etcd を変更しない。

```bash
alias cm-etcd-manage='/cm/local/apps/cmd/scripts/cm-etcd-manage'
cm-etcd-manage --help
```

`status` 以外にもクラスタ状態を変える subcommand がある。対象 cluster、etcd quorum、バックアップ先、復旧手順を確認する前に `add`、`remove`、`promote`、`move-leader`、`restore` を試行しない。

## 2026-09-25 の調査実施記録

- 実行者: Codex
- 目的・対象: 別環境で `cm-etcd-manage` が見つからない事象について、コマンド置換の有無と切り分け方法を確認する
- 実行場所・権限: 本リポジトリがある BCM 11 ヘッドノードの root shell。リポジトリと製品資料は読み取り、`docs/` の更新と Git commit に限り書き込みを行う
- 対象版: インストール済み `cmdaemon` は `11.0-165270-cm11.0-14a0291f4f`、`cm-setup` は `11.0-124257-cm11.0-7f8393643d`。以前の実機記録の `Cluster Manager 11.0` と照合した。インストーラー表示の 11.34.0 とパッケージ表示を同一表記とは扱わない
- ツール: Bash、`rg`、Git 2.43.0、Python 3.12.3。PDF 抽出には `/tmp/bcm-pdf-read` に以前用意された pypdf 6.19.0 を読み取り専用で使用した

実行順と結果:

1. `README.md`、`docs/references.md`、`docs/bcm-kubernetes-versions.md`、`docs/validation.md` と関連記述を読み、開始時の `git status --short --untracked-files=all` が空であることを確認した。
2. リポジトリと `input/10-bcm-installer-manual/` の資料を検索した。最初の Python PDF 検索は system Python に `pypdf` がなく `ModuleNotFoundError` で終了した。既存の `/tmp/bcm-pdf-read` を `PYTHONPATH` に指定して再実行し、9 冊を横断検索した。Containerization Manual の etcd 関連ページは確認できたが、対象コマンド名は全 PDF で 0 件だった。
3. NVIDIA の公開 Release Notes、現行 Containerization Manual、DGX SuperPOD / BasePOD Update Guide を確認した。BCM 11 での導入、11.34.0 での継続修正、DGX 手順に記載された配置先と alias を相互に照合した。
4. 本ヘッドで `type -a`、`command -v`、想定パスの `stat`、`dpkg-query -S` / `-W`、`dpkg-query -L`、`PATH` とプロファイル内の alias を読み取り確認した。裸のコマンドは見つからず、root 所有・mode 700 の実体と `cmdaemon` の所有関係を確認した。設定は変更していない。
5. 絶対パスの `--help` を実行し、使用方法と subcommand を確認した。実行環境では `/var/log` が読み取り専用のためログファイルを開けない警告が出たが、ヘルプは表示された。クラスタ操作は実行していない。
6. `cmsh -c 'main versioninfo'` は CMDaemon へ接続できず失敗した。続く `systemctl` の照会も実行環境から systemd bus へ接続する権限がなく失敗したため、サービス停止とは断定しない。版は `dpkg-query` の今回の結果と、`input/40-bcm-pxe/2026-09-22-headnode-check.txt` の以前の成功記録を使用した。
7. 本書を作成し、README の索引と製品資料の参照先を更新した。`git diff --check`、コードブロック、相対リンク、表の列数、UTF-8 末尾改行を確認し、問題はなかった。公開情報の補助検索では最初に `rg -E` を使用してオプション解釈エラーとなり、`rg -e` で再実行した。追加した文書の検出箇所は NVIDIA の公開 URL だけで、認証情報、個人・組織情報、実環境の接続情報、第三者原本の転載は確認されなかった。
8. 最初の `git add` は sandbox から Git index へ書き込めず失敗した。承認された Git 書き込み権限で今回の 3 ファイルだけをステージし、`git diff --cached --name-status` / `--check` / `--stat` / 全差分と作業ツリーとの一致を確認した。`git grep --cached` の補助検索、`git ls-files -- input`、`git check-ignore -v`、公開用の Git author / committer 名義も確認した。`input/` の追跡はなく、対象 PDF は `/input/` ルールで除外され、追加の匿名化や対象除外が必要な問題はなかった。この追記後に再ステージして同じ確認を繰り返す。

期待結果は置換の有無と別環境での確認順を特定すること。実際には置換を示す根拠はなく、現行ツールの配置と `PATH` の差を主要因として確認した。別環境そのものには接続していないため、その環境の BCM 版、ファイルの有無、パッケージ状態は未確認である。証跡は本タスクのツール出力、上記 Git 管理外の既存実機記録、公式 URL、今回の Git 差分である。
