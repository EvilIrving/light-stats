# Light Stats

Light Stats は、「いま Mac に負荷がかかっているか」を示すネイティブ macOS メニューバー型システムモニターです。使用量の多寡ではなく応答性の圧迫に注目します。0〜100 の健康度と CPU・GPU・メモリ圧迫などのリアルタイム信号がメニューバーに常駐し、ポップオーバーを開けば全体像（ディスクとディスク I/O、ネットワーク、プロキシと出口ノードの状態、バッテリー、温度、ファン、上位プロセス、AI CLI 使用量）を確認できます。

[English](README.md) · [简体中文](README.zh.md) · **日本語** · [한국어](README.ko.md)

---

## デモ

https://github.com/user-attachments/assets/f167325d-e972-42fe-a54f-17a8a7a40834

---

## スクリーンショット

| 概要 | クリーンアップ |
|------|------|
| <img src="docs/screenshots/popover-overview.png" width="320" alt="概要パネル" /> | <img src="docs/screenshots/popover-cleanup.png" width="320" alt="クリーンアップパネル" /> |

---

## 概要

Light Stats は Mac のライブな負荷シグナルをメニューバーに常時表示し、必要なときに詳細な浮動パネルを開けます。Activity Monitor を開きっぱなしにせず状態をすばやく確認したいユーザーや、ネイティブな SwiftUI/AppKit メニューバー実装を参考にしたい開発者に向けて設計されています。

通常のサンプリングには macOS ネイティブ API を使用し、サードパーティのランタイム依存はありません。ネットワークを伴う診断機能は既定でオフです。

---

## 機能

### メニューバー

- 固定幅の数値でレイアウトのちらつきを抑えるコンパクトな 2 行表示
- Logo・CPU・GPU・メモリ・ディスク・ネットワーク・ファン・バッテリー・健康度を任意に表示
- アップロード／ダウンロード速度表示
- ファン状態を回転アイコン風に表示
- 0〜100 の健康度スコアを任意表示

### 概要パネル

- CPU・GPU・メモリ圧迫・スワップ活動・ロードアベレージ
- P/E コア使用率グラフと CPU プロセスランキング
- 対応機種ではバッテリー状態・残量・充放電回数・健康度・消費電力・温度
- ディスク容量と集約ディスク I/O 速度
- ネットワーク速度・ローカルプロキシ状態・任意の公開出口ノード情報
- 温度・ファン・熱状態・ディスク状態のステータスバー
- システム健康度スコア、各次元の概要、次元ごとの切り替え
- AI 監視を有効にすると Claude Code・Codex・Gemini のサブスクリプション使用量

### メモリクリーンアップ

- メモリ圧迫状況とスワップ警告
- メモリ使用量順に並べた App 一覧
- 通常終了と確認付きの強制終了
- 子プロセスの詳細を展開表示

### ウィンドウ操作

- デザイナー提供のアイコン付きウィンドウ操作メニュー
- 左半分・右半分・上半分・下半分だけにショートカットを割り当て、高頻度操作を優先
- 角、三分割、ディスプレイ移動、最大化、中央配置、復元、最小化をメニューから実行
- タイトルバー上のトラックパッドジェスチャーでスナップし、プレビューと触覚フィードバックを表示
- ウィンドウ操作、グローバルショートカット、タイトルバージェスチャーにはアクセシビリティ権限が必要

### スクロール方向制御

- 垂直／水平スクロール方向の反転
- スクロール量を調整するステップ倍率
- 関連機能が有効なときだけイベント tap を起動

### 清掃モード

- キーボード清掃のために 60 秒間キーボード入力をロック
- 全画面の半透明オーバーレイとカウントダウン
- マウスだけで終了できるボタン。キーボード入力は抑止
- CGEventTap を使用し、アクセシビリティ権限が必要

### 自動更新

- GitHub Releases で新バージョンを確認
- DMG をダウンロードし、codesign 署名・公証・Team ID を検証
- アプリ終了後に独立スクリプトで app bundle を置き換え
- ダウンロードとインストール中は軽量な進捗ウィンドウを表示

### ネットワークとプロキシ

Light Stats は環境変数・システムプロキシ設定・アクティブなトンネルインターフェースからローカルプロキシ構成を検出します。この処理で外部リクエストは発生しません。

公開出口ノードの検出は任意です。有効にすると、選択した geo-IP プロバイダに公開 IP・位置・ASN・ISP を照会し、結果をキャッシュして繰り返しの要求を避けます。

### AI サブスクリプション使用量

有効にすると、Light Stats は Claude Code・Codex・Gemini の CLI がローカルに保存した認証情報を読み取り、現在のサブスクリプション利用率を概要パネルに表示します。AI 監視は既定でオフで、認証情報は各プロバイダ自身の使用量エンドポイント以外には送信されません。

### 健康度スコア

健康度スコアは CPU、メモリ圧迫とスワップ、ロードアベレージ、温度、GPU、電源状態を 0〜100 のスコアに集約します。ディスク容量のような変化の遅い数値ではなく、現在の応答性に影響する圧迫シグナルを重視します。ノート Mac ではバッテリー状態、デスクトップ Mac ではディスク I/O 圧迫を電源次元として扱います。欠落または無効化された次元の重みは自動的に再配分されます。

---

## プライバシー

Light Stats にはリモートテレメトリはありません。ローカルシステム指標、ローカルプロキシ検出、プロセス一覧、スクロール動作、ウィンドウ操作は Mac 上に留まります。

出口ノード検出は既定でオフです。有効にすると、アプリは選択した geo-IP プロバイダにリクエストを送り、現在の公開 IP とネットワークの所有者を識別します。結果は 60 秒間キャッシュされ、失敗時は静かにフォールバックします。

AI 使用量監視は既定でオフです。有効にした場合、リクエストは各プロバイダ自身の使用量エンドポイントにのみ送られ、各 CLI が既にローカルに保存している認証情報を使用します。

更新確認では GitHub Releases に接続します。

---

## 設定

- メニューバー項目の表示切り替え
- 更新頻度：低 (5s)、中 (2s)、高 (1s)
- 温度単位：摂氏または華氏
- ネット速度単位：自動、KB/s、MB/s
- 出口ノード検出とプロバイダの選択
- Claude Code・Codex・Gemini の AI 監視切り替え
- 垂直スクロール反転、水平スクロール反転、ステップ倍率
- ウィンドウショートカットとタイトルバージェスチャー
- 健康度スコアの次元切り替え
- 言語：简体中文、English、日本語、한국어、システム言語

---

## 開発

詳しくは [CONTRIBUTING.md](CONTRIBUTING.md) を参照してください。

### 動作要件

- macOS 14+
- Xcode 16 以降を推奨
- Swift 5.9+
- ローカル lint には SwiftLint (`brew install swiftlint`)

### ビルド

```bash
# 最新の Debug app をビルドして起動
./debug-run.sh

# 手動 Debug ビルド
xcodebuild -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -configuration Debug \
  -derivedDataPath build/DerivedData build

# Release DMG
./build.sh
```

### 品質チェック

```bash
swiftlint lint --strict
./validate_localization.sh
```

GitHub Actions は SwiftLint、ローカライズ検証、Release ビルド、成果物アップロード、タグでの署名／公証、GitHub Release 作成を実行します。

### テスト

最小限の XCTest は `LightStatsTests/LightStatsSmokeTests.swift` にあります。

```bash
xcodebuild test \
  -project "Light Stats.xcodeproj" \
  -scheme "Light Stats" \
  -destination 'platform=macOS'
```

### 技術スタック

- パネルと設定に SwiftUI
- メニューバー統合、ポップオーバー、オーバーレイ、カスタムビューに AppKit
- Combine と Swift Concurrency
- Mach API、IOKit、Accessibility、Core Graphics event tap、CFNetwork、Network、SMC、getifaddrs
- サードパーティのランタイム依存なし

### アーキテクチャ

アプリはモデル・サービス・ビューモデル・ビューの層に分かれています。`SystemMonitor` がサンプリングを統括して UI にスナップショットを発行し、各サービスが対応する指標を収集します。

キャッシュや非同期が必要な収集器（出口ノード照会や AI 使用量プロバイダなど）は actor を使用します。UI に紐づく状態は main actor に留めます。高速な syscall ヘルパーは適切な場面で同期のまま保ちます。

### プロジェクト構成

- `Light Stats/Models/`: 指標データ構造、健康度、リリース情報
- `Light Stats/Services/`: システム収集、スコアリング、更新、スクロール、ウィンドウ操作、キーボードロック、AI 使用量
- `Light Stats/ViewModels/`: アプリ状態、サンプリング、設定、清掃モード、更新統括
- `Light Stats/Views/StatusBar/`: メニューバー描画
- `Light Stats/Views/Popover/`: 浮動パネル UI と再利用コンポーネント
- `Light Stats/Views/Settings/`: 設定 UI
- `Light Stats/Views/About/`: About ウィンドウ
- `Light Stats/Views/CleaningMode/`: 清掃モードオーバーレイ
- `Light Stats/Views/Update/`: 更新進捗ウィンドウ
- `Light Stats/Resources/`: ローカライズ文字列とウィンドウ操作アイコン
- `LightStatsTests/`: XCTest smoke tests
- `.github/workflows/`: ビルド、デプロイ、リリース自動化

---

## ロードマップ

- より詳細なネットワーク診断
- Intel・Apple Silicon・ノート・デスクトップ Mac でのさらなる検証
- App ごとのネットワーク使用量
- より細かなクリーンアップ提案
- ウィンドウジェスチャーとメニューバー密度の継続的な調整
