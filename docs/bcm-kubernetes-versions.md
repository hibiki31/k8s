# BCM と Kubernetes のバージョン対応（Ubuntu 24.04）

確認日: 2026-09-22。対象は **Ubuntu 24.04 上の BCM 11.34 / 11.33 と、BCM の `cm-kubernetes-setup` による Kubernetes 導入**。公式資料の調査結果であり、本環境でのインストール・動作確認結果ではない。

## 比較の要点

**両方の BCM で Kubernetes 1.34 系を使用する公式の導入例がある。現行 BCM 11 マニュアルの導入候補は 1.34 / 1.35 / 1.36 だが、各 ISO・パッケージで選択できる全バージョンは実機確認が必要。** BCM の `11.34` / `11.33` と Kubernetes の `1.34` / `1.33` は別の番号で、一対一の対応ではない。

| BCM | Ubuntu 24.04 で具体的に確認できた Kubernetes 導入例 | それ以外のバージョンの扱い |
|---|---|---|
| **11.34.0** | **1.34 系**。Mission Control の公式手順が BCM 11.34 / Ubuntu 24.04 / Kubernetes 1.34 を参照構成として明記 | 現行 BCM 11 マニュアルでは **1.34 / 1.35 / 1.36** を掲載。11.34 の導入候補として確認し、使用するパッケージの選択肢と照合する |
| **11.33.0 / 11.33.1** | **1.34.7**。BCM マニュアル付録 B が両パッチ版と Ubuntu 24.04 を明記 | **1.34 だけに限定されるという意味ではない**。11.33 の各パッケージが提供する全選択肢は未確認。11.33.1 に関する AI Enterprise の対応範囲は後述 |

根拠: [BCM 11.34 の公式導入手順・Reference environment](https://docs.nvidia.com/mission-control/docs/nmc-software-installation-guide/2.3.0/airgapped-installation/staging-and-installing-artifacts.html#reference-environment)、[BCM 11 Containerization Manual](https://docs.nvidia.com/base-command-manager/manuals/11/containerization-manual.pdf) 第4章 pp.27–29・付録 B p.189。これらの導入例は air-gap 構成を含み、採用版の上限・下限を網羅した表ではない。

## 認定表示と推奨・テスト済みバージョン

**BCM の一覧で `NVIDIA AI Enterprise certified` と明記されているのは、現行マニュアルの例では Kubernetes 1.34 / 1.35。** ここでの「認定」はこの表示を指す。Containerization Manual 第4章 p.27 の `cm-kubernetes-setup --list-versions` 出力例で確認でき、§4.2.8 p.42 ではウィザードの認定版を `*` で示すと説明されている。

| Kubernetes マイナーバージョン | 現行 BCM 11 マニュアルの認定表示 | 資料に記載された推奨・テスト済みパッチ |
|---|---|---|
| **1.34** | **NVIDIA AI Enterprise certified** | **1.34.10** |
| **1.35** | **NVIDIA AI Enterprise certified** | **1.35.7** |
| 1.36 | 出力例に認定表示なし | **1.36.3** |

パッチ番号は §4.2 p.29 に記載された **2026年8月時点**の推奨・テスト済み値。認定表示はマイナー版に付いており、この表だけで各系列のすべてのパッチ版が認定済みとは判断しない。また、1.36 は導入候補・テスト済みとして掲載されているが、この出力例では認定表示がない。後述のサポート表への掲載とは区別する。

この表は **BCM 11 の現行資料の表示例**であり、BCM 11.34 / 11.33 それぞれの ISO・更新状態に対する認定一覧ではない。各環境では `cm-kubernetes-setup --list-versions` の認定表示も確認する。特に、11.33 の出荷時の内容や、本環境の選択結果として扱わない。

実際の選択肢はインストール済みパッケージに依存する。マイナー版を選んだ後、ウィザードで提示されるパッチ版も確認する。表のパッチ番号は調査対象資料の値であり、常に最新であることを意味しない。

### AI Enterprise の対応表との違い

[NVIDIA AI Enterprise 8.2 Support Matrix](https://docs.nvidia.com/ai-enterprise/release-8/latest/support/support-matrix-8/8.2.html) は、Table 4 に **BCM 11.33.1**、Table 11「Base Command Manager」に **Kubernetes 1.32–1.36 / Containerd / Ubuntu 24.04 LTS** を掲載している。

これは AI Enterprise のサポート構成の情報で、BCM の新規導入ウィザードの選択肢一覧や認定マークとは対象が異なる。サポート表への掲載だけで、すべての版に BCM の `certified` 表示が付くとは判断しない。したがって、11.33.1 で 1.35 / 1.36 を非対応とは断定しない一方、11.33 の未更新 ISO から 1.32–1.36 のすべてを導入できるとも断定しない。11.33.0 への適用も別途確認する。

## 実機で確定する方法

以下は **Ubuntu 24.04 の BCM ヘッドノード**で、BCM と管理ツールが導入済みであることを前提とする確認用コマンド。今回の調査では未実行。

```bash
# BCM のバージョン情報
cmsh -c "main versioninfo"

# Kubernetes 構築ツールを含むパッケージの実バージョン
dpkg-query -W -f='${Package}\t${Version}\n' cm-setup

# この環境の BCM が提示する Kubernetes バージョンと認定表示
cm-kubernetes-setup --list-versions
```

`versioninfo` に加えて `cm-setup` の版も記録する。ISO 名やインストーラーの表示だけで、更新後の構築ツールの版や導入候補は確定できない。`--list-versions` の出力と、構築時に提示されるパッチ版を記録してから採用版を決める。air-gap 構成では、その版に対応するパッケージとコンテナイメージ等の準備も必要。

本環境の採用版・構成は [環境構成](environment.md#ソフトウェアと設定の確定状況)、導入・動作確認の進捗は [検証状況](validation.md) で管理する。今回の調査だけでは、Multus / TopoLVM の各版との互換性や、本環境での構築成功は確定しない。

## 参照資料

PDF のページは表紙を1ページとする通し番号で、以下の参照箇所は紙面のページ番号とも一致する。公開 Web 資料の閲覧日はすべて 2026-09-22。

| 資料 | 版・参照箇所 | 確認内容 |
|---|---|---|
| `input/10-bcm-installer-manual/containerization-manual.pdf` | BCM 11、Revision `47eff3c`、2026-09-21。第4章 p.27、§4.2 pp.28–29、付録 B p.189 | 導入候補、認定表示、パッチ版、パッケージ依存、11.33.0 / 11.33.1 の導入例 |
| [公開版 Containerization Manual](https://docs.nvidia.com/base-command-manager/manuals/11/containerization-manual.pdf) | BCM 11、Revision `1e6a090`、2026-09-22。同じ章・ページと §4.2.8 p.42 | 上記のバージョン・認定表示を照合。ウィザードの認定マークの説明も確認。手元 PDF とは別リビジョン |
| `input/10-bcm-installer-manual/installation-manual.pdf` | BCM 11、Revision `47eff3c`、2026-09-21。§4.2.3 pp.61–62 | `versioninfo` による BCM ソフトウェア版の確認。ライセンス版とは区別 |
| [BCM 11.34.0 Release Notes](https://docs.nvidia.com/base-command-manager/bcm-11-release-notes/bcm11-34-0.html) | 2026-09-11 リリース、cm-kubernetes-setup 節 | 非 air-gap 構成でも Kubernetes マイナー版を固定する変更 |
| [BCM 11.33.0 Release Notes](https://docs.nvidia.com/base-command-manager/bcm-11-release-notes/bcm11-33-0.html) / [11.33.1 Release Notes](https://docs.nvidia.com/base-command-manager/bcm-11-release-notes/bcm11-33-1.html) | それぞれ 2026-05-29 / 2026-06-24 リリース | 11.33 系のパッチ版を区別。11.33.0 には Ubuntu 24.04.4 への更新を記載 |
| [Mission Control: Staging and Installing Artifacts](https://docs.nvidia.com/mission-control/docs/nmc-software-installation-guide/2.3.0/airgapped-installation/staging-and-installing-artifacts.html) | URL の資料版 2.3.0、ページ更新日 2026-09-11。Reference environment、Step 1 | BCM 11.34 / Ubuntu 24.04 / Kubernetes 1.34 の導入例 |
| [NVIDIA AI Enterprise 8.2 Support Matrix](https://docs.nvidia.com/ai-enterprise/release-8/latest/support/support-matrix-8/8.2.html) | Table 4、Table 11 | BCM 11.33.1 と、BCM 上の Kubernetes 1.32–1.36 / Ubuntu 24.04 のサポート構成 |
| [BCM Feature Matrix](https://service.bcm.nvidia.com/feature-matrix/) | Base Command Manager 11、OS Family: UBUNTU、Containerization → Kubernetes | Ubuntu 24.04 の x86_64 / AArch64 に対応マークあり。11.33 / 11.34 別の Kubernetes バージョン表ではない |
