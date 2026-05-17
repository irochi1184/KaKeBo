# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

KaKeBo は iOS 向け家計簿アプリ。SwiftUI + MVVM 構成で、CoreData を使わず JSON ファイルベースでデータを永続化。

- **Bundle ID**: `com.irochi.KaKeBo`
- **Deployment Target**: iOS 17.6（iOS 26 対応）
- **現在のバージョン**: 2.3
- **言語**: Swift / SwiftUI
- **外部依存**: なし（SPM / CocoaPods 不使用）
- **AppGroup ID**: `group.com.irochiTech.KaKeBo`（`Shared/AppGroup.swift`）

## ビルド

```bash
# シミュレータ（環境によってはSDKバージョン不一致でビルド不可の場合あり）
xcodebuild -scheme KaKeBo -destination 'platform=iOS Simulator,name=iPhone 16' build

# 汎用ビルド（コード署名なし、コンパイル確認用）
xcodebuild -scheme KaKeBo -destination 'generic/platform=iOS' build CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

テストターゲットは未構成。ビルド確認は Xcode 上で行うのが確実。

## アーキテクチャ

### ディレクトリ構成

```
KaKeBo/
├── App/           # @main、AppDelegate、CloudKit共有受付、UpdateNotice
├── Models/        # Codable データモデル
├── Services/      # ObservableObject ストア群（中央データ管理）
├── Views/         # SwiftUI ビュー（タブ別サブフォルダ）
│   ├── Calendar/
│   ├── Components/
│   ├── History/
│   ├── Paywall/
│   ├── Receipt/
│   ├── Security/
│   ├── Settings/
│   └── Shared/
├── Utilities/     # ヘルパー群
│   ├── OCR/       # ReceiptParser, PaymentScreenshotParser
│   └── Security/  # AppLockManager, Keychain
KaKeBoWidget/      # WidgetKit ターゲット
Shared/            # アプリ・Widget共有コード（AppGroup, TransactionDTO）
```

### Xcode プロジェクト構成の注意点

- **フォルダ参照方式**: `project.pbxproj` には各 Swift ファイルの個別登録がない。フォルダ内に置くだけで自動的にビルド対象になる
- ターゲット: `KaKeBo`（メインアプリ）, `KaKeBoWidgetExtension`（ウィジェット）

### データフロー

1. **DataStore**（`Services/DataStore.swift`）が取引・カテゴリ・予算・テンプレートを管理
2. AppGroup コンテナ内の JSON（`categories.json`, `transactions.json`, `budgets.json`）に読み書き
3. View は `@EnvironmentObject` で参照
4. 保存後に `WidgetCenter.shared.reloadAllTimelines()` でウィジェット更新

### EnvironmentObject（KaKeBoApp.swift で注入）

| Object | 役割 |
|--------|------|
| `DataStore` | 取引・カテゴリ・予算・よく使うテンプレート |
| `ThemeStore` | テーマ設定（standard/business） |
| `SharedLedgerStore` | CloudKit 共有家計簿 |
| `PurchaseManager` | StoreKit 2 課金管理 |
| `LedgerContext` | 個人/共有の帳簿モード切替 |
| `AppLockManager` | パスコードロック |
| `MonthStartStore` | 月開始日設定 |
| `AppRoute` | ディープリンク・タブ遷移 |

### タブ構成（RootTabView）

ホーム / カレンダー / レポート / 履歴 / 設定

### 重要パターン

- **MonthStartResolver**: カスタム月開始日に基づいて月の範囲を計算する。月に関する計算は必ず `monthStartStore.resolver()` 経由で行うこと
- **UserDefaults.appGroup**: アプリ設定の保存先。`migrateIfNeeded(keys:)` で旧 standard からの移行を行う
- **DashboardCard enum**: HomeView のカード並び替え。新カード追加時は `visibleCardsInOrder()` と `render()` 両方の switch に追加が必要
- **FixedExpenseTemplate の保存**: `UserDefaults.appGroup` の `DataStore.fixedTemplatesKey` キーに JSON で保存（DataStore のプロパティではない）

### 課金（PurchaseManager）

- 月額: `kakebo.premium.monthly`
- 年額: `kakebo.premium.yearly`
- 買い切り: `kakebo.premium.lifetime`
- `purchase.isPremiumActive` で機能制限判定

## コーディング規約

- コメント・UIテキストは日本語（ロケール `ja_JP` 固定）
- データモデルは `Codable` 準拠、ID は `UUID`
- ファイル保存は AppGroup コンテナ直下の JSON
- 新しい View を追加する場合、既存の `.homeCard()` modifier や `LuxTheme` スタイルを踏襲する
- `@EnvironmentObject` を新しい View で使う場合、sheet 呼び出し元で `.environmentObject()` を渡すこと

## Git ワークフロー

- `main`: リリースブランチ（PR は全て main へマージ）
- Feature: `feature/機能名` → PR → merge --delete-branch
- Fix: `fix/修正内容` → PR → merge --delete-branch
- コミットメッセージ: `feat:` / `fix:` / `docs:` プレフィックス（日本語本文）
- PR 作成後、`gh pr merge N --merge --delete-branch` でマージ

## よくある落とし穴

- **DashboardCard の switch 漏れ**: enum にケースを追加したら `visibleCardsInOrder()` と `render()` 両方に追加すること
- **EnvironmentObject 未注入**: sheet/NavigationLink 先で使う場合は呼び出し元で明示的に渡す
- **ビルドエラー（シミュレータ不可）**: iOS SDK バージョンとCoreSimulator の不一致がある場合は `generic/platform=iOS` で署名なしビルドか Xcode 上で確認
- **UserDefaults キーの移行**: 新しい AppStorage キーを追加する場合は `migrateIfNeeded` で旧データからの移行を考慮

## アップデート通知の管理

`App/UpdateNotice.swift` の `defaultHighlights` 配列を差し替えることで、バージョンアップ時のお知らせ内容を変更できる。過去のバージョン内容はコメントブロックに履歴として残す。
