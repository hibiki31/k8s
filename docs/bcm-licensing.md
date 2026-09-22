# BCM ライセンス登録手順と実施記録

実施日: 2026-09-22（JST）。対象は BCM ヘッドノード、BCM 11 / Ubuntu 24.04。利用者が実行した端末ログと、同日 23:26 の読み取り専用確認に基づく。ライセンス登録は実施済みであり、以下を再実行する必要はない。現在の有効性・上限と進捗は [検証状況](validation.md) に集約する。

プロダクトキー、シリアル、組織・所在地、ライセンスのクラスタ識別名は公開文書では匿名化する。`<...>` は実値を除去したプレースホルダーであり、そのまま入力する値ではない。証明書・秘密鍵・CSR の内容は転記しない。

## 前提と実行場所

- 発行済みのプロダクトキーを用意する。取得方法と資料は [製品資料](references.md#ライセンスの取得と登録) を参照する。
- **BCM ヘッドノードの root の OS シェル**で実行する。`request-license` は cmsh のサブコマンドではない。
- 登録では認証用の鍵・証明書が更新され、CMDaemon が再起動する。今回は計算ノードの OS 展開前に実施した。
- MAC はヘッドノードに存在し、継続して使用する NIC のものを指定する。本環境では実測した `enp1s0` の `52:54:00:64:00:10` を使用した。内部・外部の旧計画と実測の差は [環境構成](environment.md#2026-09-22-の稼働後確認) を参照する。

## 1. cmsh を終了して登録コマンドを実行する

今回、最初に cmsh 内で実行したため `Command not found: request-license` になった。`exit` で OS シェルへ戻り、同じコマンドを実行すると対話入力へ進んだ。

```text
[<HEADNODE_HOSTNAME>]% request-license
Command not found: request-license
[<HEADNODE_HOSTNAME>]% exit
root@<HEADNODE_HOSTNAME>:~# request-license
```

OS シェルからの実行コマンドは以下。

```bash
request-license
```

## 2. 登録情報を入力する

以下は利用者提供ログで確認できた操作。再利用の確認画面は今回のログにはなく、新しい秘密鍵が生成された。

| 項目 | 操作と実際の結果 |
|---|---|
| Product Key | 発行済みキーを対話入力。実値は非掲載 |
| Country / State / Locality / Organization / Organizational Unit | 登録情報を入力。個人・組織情報を避けるため実値は非掲載 |
| Cluster Name | 最初の空入力では再度入力を要求され、その後 `<CLUSTER_NAME>` を入力。証明書の Common name に反映された。OS ホスト名を変更した操作ではない |
| 秘密鍵生成 | `/cm/local/apps/cmd/etc/cluster.key.new` への保存表示あり。内容は参照・公開しない |
| Primary head node MAC | `enp1s0` の既定値 `52:54:00:64:00:10` を Enter で採用 |
| ヘッド 2 台の HA | `[y/N]` に Enter、既定の No。Kubernetes のコントロールプレーン台数とは独立 |
| CSR 生成 | `/cm/local/apps/cmd/etc/cluster.csr.new` への保存表示あり。CSR にもキー・識別情報が含まれ得るため公開しない |
| 要求送信 | `[Y/n]` に Enter、既定の Yes。続いて `License granted.` を確認 |

## 3. 発行されたライセンスをインストールする

`/cm/local/apps/cmd/etc/cluster.pem.new` への保存表示後、`Install license?` に `y`、証明書情報を確認して `Is the license information correct?` に `Y` を入力した。

発行画面では `Edition: Advanced`、`License type: Free`、`Licensed tokens: 10` を確認した。「試用版を取得した」という利用者の説明と、実際に表示された種別を区別し、記録には製品の表示を用いる。`Licensed tokens` の数だけからノード上限を推定せず、登録後の `Licensed nodes` で確認する。証明書の Version 10 はライセンス形式であり、導入済み BCM の製品版を 10 に変更したことを意味しない。

利用者提供ログには以下の成功表示がある。

- 旧ライセンスを `/var/spool/cmd/backup/certificates/2026-09-22_23.23.06` に退避。バックアップ内容は今回調査していない。
- 新ライセンスをインストールし、既存 CMD 証明書を失効。
- CMDaemon の停止、管理者証明書のインストール、CMDaemon の起動を実施。停止・起動とも `OK`。
- `default-image` と `node-installer` にクラスタ証明書をコピー。
- 利用者証明書の再生成を表示。個々の利用者による接続は再検証していない。

## 4. 登録後に実機で確認する

以下は **BCM ヘッドノードの OS シェル**から実行済み。`cmsh -c` を通じて BCM の状態を照会する。

```bash
verify-license verify
cmsh -c 'main licenseinfo'
systemctl is-active cmd
cmsh -c 'device list'
cmsh -c 'device newnodes'
```

`verify-license verify` は終了コード 0、`cmd` は active、ヘッドは UP。ノード数と確認時点の有効性は [検証状況](validation.md) に記録した。正確な有効期間は Git 管理外の証跡に保持し、公開文書では省略する。CMDaemon の active 移行時刻は同日 23:24:16 JST。ライセンス再申請・再インストールやサービス再起動は確認作業では行っていない。

さらに、稼働ヘッドの `/cm/local/apps/cmd/etc/cluster.pem` と、以下のファイルの内容一致を読み取り専用で確認した。証明書そのものは公開しない。

- `/cm/images/default-image/cm/local/apps/cmd/etc/cluster.pem`
- `/cm/node-installer/cm/local/apps/cmd/etc/cluster.pem`

公開 Web の無償ライセンスの一般条件と、今回発行された期限・上限が異なる場合は、実際の表示を本環境の確認結果として保持する。一般説明だけで実測値を上書きしない。

## 5. 計算ノードとスイッチの証明書更新の扱い

インストール後の案内には計算ノードの一括再起動と、cm-lite-daemon が動作するスイッチの証明書再要求が表示された。これらは **実行したログではなく、後続操作の案内**。

今回の確認では `node001`～`node006` は全台 MAC 未登録・DOWN / unassigned、`device newnodes` は空。展開済み計算ノードは確認されていないため、`pdsh -g computenode reboot` は実行していない。次の [PXE・OS 展開](bcm-pxe-provisioning.md) でノードを登録・起動し、新しいノード証明書の取得と管理通信を確認する。

スイッチ向けの再要求も実行していない。本環境の libvirt 仮想ネットワークを、cm-lite-daemon を実行する管理対象スイッチと同一視しない。既に展開済みの計算ノードや該当スイッチが別に存在する場合は、その対象を確認して証明書更新・再起動を計画する。

## 証跡と資料

- `input/50-bcm-license/2026-09-22-registration-transcript-redacted.txt`: 利用者提供ログの匿名化転記。実施日 2026-09-22、旧証明書バックアップ名の時刻 23:23:06。入力値と生成物の保存表示、成功表示、後続操作の案内を区別した。
- `input/50-bcm-license/2026-09-22-post-registration-check.txt`: 同日 23:26 JST の実機照会結果。識別情報を除いたライセンス属性、各コマンドの終了コード、サービス・ノード状態、証明書の一致判定を保存。
- `input/10-bcm-installer-manual/installation-manual.pdf`: BCM 11 / Revision `47eff3c` / 2026-09-21、§4.3.2–4.3.4 pp.62–66、§4.3.7 pp.67–68。PDF 通し番号と紙面番号は一致。資料の登録・証明書更新手順と今回のログを照合した。

`input/` は全体を Git 管理外とし、秘密鍵・CSR・証明書・旧証明書バックアップを Git 管理する場所へ複製しない。
