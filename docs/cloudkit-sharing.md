# CloudKit 共有機能の設計メモ（KaKeBo）

## 1. 現行実装の共有方式
- **record hierarchy sharing（レコード階層共有）** を採用しています。
- `SharedTransaction` と `SharedCategory` は `record.parent` に `SharedLedger` を設定しており、`CKShare(rootRecord: rootRecord)` で `SharedLedger` を root にして共有を作成します。
- `zone sharing`（`CKRecordZone` に対する `CKShare(recordZoneID:)`）は使っていません。

## 2. 保存先の整理
- 共有作成時の root record（`SharedLedger`）と `CKShare` は、**オーナーの privateCloudDatabase** に保存します。
- 共有参加者は **sharedCloudDatabase** から、共有された `SharedLedger / SharedCategory / SharedTransaction` を参照します。

## 3. DBの使い分けルール
- 個人家計簿: 既存の個人用データストア（CloudKit共有対象外）
- 自分所有の共有家計簿: `privateCloudDatabase`
- 参加中の共有家計簿: `sharedCloudDatabase`

`SharedLedgerStore` では `LedgerSource` を `private / shared` で保持し、
`database(for:)` で保存先/取得先 DB を切り替えます。

## 4. 招待受諾後の再取得フロー
1. 招待URLから `CKShare.Metadata` を解決
2. `CKAcceptSharesOperation` で受諾
3. `reloadLedgers()` を実行
4. `refreshCachedRecords()` でカテゴリ・取引を再取得
5. `lastAcceptedLedgerID` によりUI側の選択状態を共有家計簿へ反映

## 5. quotaExceeded の扱い
- `acceptShare`, `prepareShare`, `createLedger`, `addTransaction` で `CKError.quotaExceeded` を明示ハンドリング
- トースト文言を専用化（再試行目安を表示）
- ログに `operation / container / shareID / ledgerID / retryAfter` を含める
- `acceptShare` では `retryAfter` を使って自動再試行（最大6回）を行い、反映遅延時の再取得を試みます。
- 再試行回数上限に達した場合は、招待した側のiCloud空き容量確認を案内します。

## 6. Dashboard確認しやすさ
- 新規作成される recordName に接頭辞を付与
  - `ledger_...`
  - `category_...`
  - `tx_...`
- これにより Dashboard 上でレコード用途を識別しやすくしています。

## 6.1 旧バージョン互換
- `SharedLedger` 読み込み時に `ownerUserId` が欠損していても読み込めるようにし、旧データを継続利用できるようにしています。
- `acceptShare` で `acceptSharesResult` が成功した場合は、`perShareResult` の個別失敗があっても shared DB の再取得で最終状態を確認します。

## 7. CloudKit Dashboard確認手順
1. CloudKit Dashboard で対象 Environment（Development / Production）を選択
2. **Private Database** で `SharedLedgerZone` を開く
3. `SharedLedger` レコードと対応する `CKShare` が存在することを確認
4. 参加者Apple IDで招待URLを受諾
5. 参加者側の **Shared Database** で `SharedLedger / SharedCategory / SharedTransaction` が見えることを確認
6. 参加者で取引を追加し、オーナー側にも反映されることを確認
