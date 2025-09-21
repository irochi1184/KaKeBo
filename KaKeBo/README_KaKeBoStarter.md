# KaKeBo Starter (SwiftUI)

**目的**: Figma/Make のプロトタイプを SwiftUI で短期間に検証できる最小構成。  
Xcode で新規 iOS App (SwiftUI, Swift) を作成し、このフォルダの `*.swift` を `YourProject/` にドラッグ & ドロップして追加してください。

## 含まれる画面
- ホーム: 今月サマリ + 取引履歴 + 追加ボタン
- 取引追加: 日付 / 金額 / 種別(支出/収入) / カテゴリ / メモ
- カテゴリ: 一覧 + 追加/編集 (色ピッカー + SF Symbols ピッカー)
- レポート: 月別合計の簡易表示

## 保存方式
- ドキュメントディレクトリに JSON 保存 (SwiftData/Core Data へ移行しやすいよう層分け済み)

## 次の一手 (本番化チェックリスト)
- [ ] SwiftData での永続化 (スキーマ: Category, Transaction, Budget)
- [ ] 入出金別のグラフ (Charts)
- [ ] カテゴリ別円グラフ / 月切替 (SegmentedPicker)
- [ ] 検索・フィルタ / 並び替え
- [ ] 単体テスト (XCTest) / UI テスト (XCUITest)
- [ ] アプリ内課金 or 広告の実装
- [ ] ローカライズ / アクセシビリティ