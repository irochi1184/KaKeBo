//
//  Stores/SharedLedgerStore.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/25.
//

import Foundation
import CloudKit
import Combine
import SwiftUI

@MainActor
final class SharedLedgerStore: ObservableObject {
    @Published var ledgers: [SharedLedger] = []
    @Published var transactionsByLedger: [CKRecord.ID: [SharedTransaction]] = [:]
    @Published var categoriesByLedger: [CKRecord.ID: [SharedCategory]] = [:]
    @Published var isLoading = false
    @Published var lastError: Error?
    
    @Published var activeCopy: CopyState? = nil
    
    private let container: CKContainer
    private let db: CKDatabase          // 自分の private DB
    private let sharedDB: CKDatabase    // 共有で見える DB
    
    private enum LedgerSource {
        case `private`
        case shared
    }
    
    struct CopyState {
        let ledgerId: CKRecord.ID
        let ledgerName: String
        let total: Int
        var done: Int
        var isCopyingCategories: Bool
        var isCopyingTransactions: Bool
    }
    
    private var ledgerSourceMap: [CKRecord.ID: LedgerSource] = [:]
    
    init(container: CKContainer = .default()) {
        self.container = container
        self.db = container.privateCloudDatabase
        self.sharedDB = container.sharedCloudDatabase
    }
    
    private let lastOpenedLedgerKey = "LastOpenedSharedLedgerRecordName"
    
    // 最後に開いた家計簿を記録
    func rememberLastOpened(ledger: SharedLedger) {
        UserDefaults.standard.set(ledger.id.recordName, forKey: lastOpenedLedgerKey)
    }
    
    // 現在の ledgers から、最後に開いた家計簿を探す
    func findLastOpenedLedger() -> SharedLedger? {
        guard let recordName = UserDefaults.standard.string(forKey: lastOpenedLedgerKey) else {
            return nil
        }
        return ledgers.first { $0.id.recordName == recordName }
    }
    
    // MARK: - Helper
    
    private func currentUserId() async throws -> String {
        let user = try await container.userRecordID()
        return user.recordName
    }
    
    private func queryRecords(_ query: CKQuery, in db: CKDatabase) async throws -> [CKRecord] {
        var allRecords: [CKRecord] = []
        
        func append(from matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)]) {
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    allRecords.append(record)
                }
            }
        }
        
        if db.databaseScope == .shared {
            // 共有DB：ゾーンごとにクエリする
            let zones = try await db.allRecordZones()
            
            for zone in zones {
                var current = try await db.records(
                    matching: query,
                    inZoneWith: zone.zoneID,
                    desiredKeys: nil,
                    resultsLimit: 0    // 0 = 上限なし
                )
                append(from: current.matchResults)
                
                while let cursor = current.queryCursor {
                    current = try await db.records(
                        continuingMatchFrom: cursor,
                        desiredKeys: nil,
                        resultsLimit: 0
                    )
                    append(from: current.matchResults)
                }
            }
        } else {
            // private / public DB：今まで通りでOK
            var current = try await db.records(
                matching: query,
                inZoneWith: nil,
                desiredKeys: nil,
                resultsLimit: 0
            )
            append(from: current.matchResults)
            
            while let cursor = current.queryCursor {
                current = try await db.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: nil,
                    resultsLimit: 0
                )
                append(from: current.matchResults)
            }
        }
        
        return allRecords
    }
    
    // MARK: - Ledger
    
    func reloadLedgers() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let userId = try await currentUserId()
            
            // ① 自分が owner の Ledger（privateDB）
            let owned = try await fetchOwnedLedgers(for: userId)
            let ownedIDs = Set(owned.map(\.id))
            
            // ② 自分に共有されている Ledger（sharedDB）
            let shared = try await fetchSharedLedgers(excluding: ownedIDs)
            
            // ③ マージして createdAt でソート
            let all = (owned + shared).sorted(by: { $0.createdAt < $1.createdAt })
            self.ledgers = all
            
        } catch {
            self.lastError = error
            print("reloadLedgers error:", error)
        }
    }

    // 自分が owner の Ledger（今までの挙動）
    private func fetchOwnedLedgers(for userId: String) async throws -> [SharedLedger] {
        // CloudKit 側では条件なしで全部取る
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: SharedLedger.recordType, predicate: predicate)
        
        let records = try await queryRecords(query, in: db)
        var result: [SharedLedger] = []
        
        for record in records {
            guard let ledger = SharedLedger(record: record) else { continue }
            
            // ① ownerUserId が設定されている場合
            if let owner = record[SharedLedger.FieldKey.ownerUserId] as? String,
               owner == userId {
                result.append(ledger)
                ledgerSourceMap[ledger.id] = .private
                continue
            }
            
            // ② ownerUserId が無い古いデータ → creator が自分ならオーナー扱い
            if let creator = record.creatorUserRecordID,
               creator.recordName == userId {
                result.append(ledger)
                ledgerSourceMap[ledger.id] = .private
                continue
            }
        }
        
        return result
    }

    // 自分が「共有されている」家計簿（受け取った側のレジャー）
    private func fetchSharedLedgers(excluding ownedIDs: Set<CKRecord.ID>) async throws -> [SharedLedger] {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: SharedLedger.recordType, predicate: predicate)
        
        let records = try await queryRecords(query, in: sharedDB)
        var result: [SharedLedger] = []
        
        for record in records {
            guard let ledger = SharedLedger(record: record) else { continue }
            guard !ownedIDs.contains(ledger.id) else { continue }
            
            result.append(ledger)
            ledgerSourceMap[ledger.id] = .shared
        }
        
        return result
    }

    // MARK: - 家計簿
    func createLedger(name: String, icon: String, colorHex: String) async -> SharedLedger? {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let userId = try await currentUserId()
            let ledger = SharedLedger.new(
                name: name,
                icon: icon,
                colorHex: colorHex,
                ownerUserId: userId
            )
            let record = ledger.makeRecord()
            
            let saved = try await db.save(record)
            let final = SharedLedger(record: saved) ?? ledger
            
            ledgers.append(final)
            ledgers.sort { $0.createdAt < $1.createdAt }
            
            return final
        } catch {
            self.lastError = error
            return nil
        }
    }
    
    func updateLedger(_ ledger: SharedLedger, name: String, icon: String, colorHex: String) async {
        guard isOwned(ledger) else {
            // 招待された側は編集不可にするならこう
            print("updateLedger: non-owned ledger, skip")
            return
        }
        do {
            let record = try await db.record(for: ledger.id)
            record["name"] = name as CKRecordValue
            record["icon"] = icon as CKRecordValue
            record["colorHex"] = colorHex as CKRecordValue
            let saved = try await db.save(record)
            if let updated = SharedLedger(record: saved) {
                if let idx = ledgers.firstIndex(where: { $0.id == ledger.id }) {
                    ledgers[idx] = updated
                }
            }
        } catch {
            lastError = error
        }
    }
    
    func deleteLedger(_ ledger: SharedLedger) async {
        guard isOwned(ledger) else {
            print("deleteLedger: non-owned ledger, skip")
            return
        }
        do {
            try await db.deleteRecord(withID: ledger.id)
            ledgers.removeAll { $0.id == ledger.id }
            // 必要なら関連トランザクションのキャッシュも削除
            transactionsByLedger[ledger.id] = nil
            categoriesByLedger[ledger.id] = nil
        } catch {
            lastError = error
        }
    }
    
    // MARK: - 取引
    func reloadTransactions(for ledger: SharedLedger) async {
        do {
            let ref = CKRecord.Reference(recordID: ledger.id, action: .none)
            let predicate = NSPredicate(format: "%K == %@", SharedTransaction.FieldKey.ledgerRef, ref)
            let query = CKQuery(recordType: SharedTransaction.recordType, predicate: predicate)
            
            let targetDB = database(for: ledger)
            let records = try await queryRecords(query, in: targetDB)
            
            var all: [SharedTransaction] = []
            for record in records {
                if let tx = SharedTransaction(record: record) {
                    all.append(tx)
                }
            }
            all.sort { $0.date < $1.date }
            transactionsByLedger[ledger.id] = all
        } catch {
            self.lastError = error
        }
    }
        
    func addTransaction(
        to ledger: SharedLedger,
        amount: Int,
        date: Date,
        type: SharedTransactionType,
        memo: String?,
        category: SharedCategory?
    ) async {
        do {
            let userId = try await currentUserId()
            let tx = SharedTransaction.new(
                ledgerId: ledger.id,
                amount: amount,
                date: date,
                type: type,
                memo: memo,
                categoryId: category?.id,
                categoryName: category?.name ?? "未分類",
                categoryColorHex: category?.colorHex ?? "#FF9500",
                createdByUserId: userId
            )
            let record = tx.makeRecord()
            
            let targetDB = database(for: ledger)
            let saved = try await targetDB.save(record)
            guard let final = SharedTransaction(record: saved) else {
                return
            }
            var list = transactionsByLedger[ledger.id] ?? []
            list.append(final)
            list.sort(by: { $0.date < $1.date })
            transactionsByLedger[ledger.id] = list
        } catch {
            self.lastError = error
        }
    }

    func updateTransaction(
        _ tx: SharedTransaction,
        in ledger: SharedLedger,
        amount: Int,
        date: Date,
        type: SharedTransactionType,
        memo: String?,
        category: SharedCategory?
    ) async {
        do {
            var updated = tx
            updated.amount = amount
            updated.date = date
            updated.type = type
            updated.memo = memo
            updated.categoryId = category?.id
            updated.categoryName = category?.name ?? "未分類"
            updated.categoryColorHex = category?.colorHex ?? "#FF9500"
            updated.updatedAt = Date()

            let targetDB = database(for: ledger)
            let baseRecord = try await targetDB.record(for: tx.id)
            let record = updated.makeRecord(existing: baseRecord)
            let saved = try await targetDB.save(record)
            guard let final = SharedTransaction(record: saved) else { return }

            var list = transactionsByLedger[ledger.id] ?? []
            if let idx = list.firstIndex(where: { $0.id == final.id }) {
                list[idx] = final
            } else {
                list.append(final)
            }
            list.sort { $0.date < $1.date }
            transactionsByLedger[ledger.id] = list
        } catch {
            self.lastError = error
        }
    }
    
    // MARK: - カテゴリー
    func reloadCategories(for ledger: SharedLedger) async {
        do {
            let ref = CKRecord.Reference(recordID: ledger.id, action: .none)
            let predicate = NSPredicate(format: "%K == %@", SharedCategory.FieldKey.ledgerRef, ref)
            let query = CKQuery(recordType: SharedCategory.recordType, predicate: predicate)
            
            let targetDB = database(for: ledger)
            let records = try await queryRecords(query, in: targetDB)
            
            var all: [SharedCategory] = []
            for record in records {
                if let cat = SharedCategory(record: record) {
                    all.append(cat)
                }
            }
            all.sort { $0.sortOrder < $1.sortOrder }
            categoriesByLedger[ledger.id] = all
        } catch {
            self.lastError = error
        }
    }

    @MainActor
    func createCategory(
        for ledger: SharedLedger,
        name: String,
        colorHex: String,
        icon: String
    ) async -> SharedCategory? {
        do {
            let current = categoriesByLedger[ledger.id] ?? []
            let sortOrder = (current.last?.sortOrder ?? 0) + 1
            
            let cat = SharedCategory.new(
                ledgerId: ledger.id,
                name: name,
                colorHex: colorHex,
                icon: icon,
                sortOrder: sortOrder
            )
            let record   = cat.makeRecord()
            let targetDB = database(for: ledger)
            
            let saved = try await targetDB.save(record)
            guard let final = SharedCategory(record: saved) else { return nil }
            
            var list = categoriesByLedger[ledger.id] ?? []
            list.append(final)
            list.sort { $0.sortOrder < $1.sortOrder }
            categoriesByLedger[ledger.id] = list
            
            return final
        } catch {
            self.lastError = error
            return nil
        }
    }
    
    // 更新：こちらも Optional 返すと便利
    @MainActor
    func updateCategory(
        _ category: SharedCategory,
        in ledger: SharedLedger,
        name: String,
        colorHex: String,
        icon: String
    ) async -> SharedCategory? {
        do {
            let targetDB = database(for: ledger)
            let record = try await targetDB.record(for: category.id)
            record["name"] = name as CKRecordValue
            record["colorHex"] = colorHex as CKRecordValue
            record["icon"] = icon as CKRecordValue
            
            let saved = try await targetDB.save(record)
            guard let updated = SharedCategory(record: saved) else { return nil }
            
            var list = categoriesByLedger[ledger.id] ?? []
            if let idx = list.firstIndex(where: { $0.id == updated.id }) {
                list[idx] = updated
            }
            categoriesByLedger[ledger.id] = list
            return updated
        } catch {
            self.lastError = error
            return nil
        }
    }

    private func database(for ledger: SharedLedger) -> CKDatabase {
        switch ledgerSourceMap[ledger.id] {
        case .shared: return sharedDB
        default:      return db
        }
    }
    
    func deleteCategory(_ id: CKRecord.ID, from ledger: SharedLedger) async {
        do {
            let db = database(for: ledger)
            
            // ① カテゴリレコードを削除
            try await db.deleteRecord(withID: id)
            
            // ② このカテゴリに紐づく取引を削除
            let ledgerRef = CKRecord.Reference(recordID: ledger.id, action: .none)
            let catRef    = CKRecord.Reference(recordID: id, action: .none)
            
            let predicate = NSPredicate(
                format: "%K == %@ AND %K == %@",
                SharedTransaction.FieldKey.ledgerRef, ledgerRef,
                SharedTransaction.FieldKey.categoryRef, catRef
            )

            let query = CKQuery(
                recordType: SharedTransaction.recordType,
                predicate: predicate
            )
            
            let records = try await queryRecords(query, in: db)
            let txRecordIDs = records.map(\.recordID)
            if !txRecordIDs.isEmpty {
                _ = try await db.modifyRecords(saving: [], deleting: txRecordIDs)
            }
            
            // ③ ローカルキャッシュからも削除
            var cats = categoriesByLedger[ledger.id] ?? []
            cats.removeAll { $0.id == id }
            categoriesByLedger[ledger.id] = cats
            
            if var txs = transactionsByLedger[ledger.id] {
                txs.removeAll { $0.categoryId == id }
                transactionsByLedger[ledger.id] = txs
            }
            
        } catch {
            lastError = error
            print("deleteCategory failed:", error)
        }
    }
    
    func isOwned(_ ledger: SharedLedger) -> Bool {
        ledgerSourceMap[ledger.id] != .shared
    }
}

extension SharedLedgerStore {
    struct SharePayload {
        let share: CKShare
        let rootRecord: CKRecord
    }
    
    /// 個人用カテゴリ・取引のコピーを「裏で」開始する
    func startInitialCopy(
        from dataStore: DataStore,
        to ledger: SharedLedger,
        copyCategories: Bool,
        copyTransactions: Bool
    ) {
        // total 件数を先に計算
        let totalCats = copyCategories ? dataStore.categories.count : 0
        let totalTx   = copyTransactions ? dataStore.transactions.count : 0
        let total = totalCats + totalTx
        
        guard total > 0 else { return }
        
        // 進捗初期化
        activeCopy = CopyState(
            ledgerId: ledger.id,
            ledgerName: ledger.name,
            total: total,
            done: 0,
            isCopyingCategories: copyCategories,
            isCopyingTransactions: copyTransactions
        )
        
        // 非同期で実行（ただし @MainActor 上で動く）
        Task {
            await self.performInitialCopy(
                from: dataStore,
                to: ledger,
                copyCategories: copyCategories,
                copyTransactions: copyTransactions
            )
        }
    }
    
    private func performInitialCopy(
        from dataStore: DataStore,
        to ledger: SharedLedger,
        copyCategories: Bool,
        copyTransactions: Bool
    ) async {
        // まずカテゴリ
        if copyCategories {
            let existing = categoriesByLedger[ledger.id] ?? []
            
            for cat in dataStore.categories {
                // あなたの Category モデルに合わせて調整
                let name = cat.name
                let icon = cat.symbolName
                let colorHex = cat.colorHex
                
                if existing.contains(where: { $0.name == name }) {
                    // 既にある名前はスキップ
                    incrementCopyDone()
                    continue
                }
                
                _ = await createCategory(
                    for: ledger,
                    name: name,
                    colorHex: colorHex,
                    icon: icon
                )
                incrementCopyDone()
            }
        }
        
        // 共有側のカテゴリ一覧を更新しておく
        await reloadCategories(for: ledger)
        let sharedCategories = categoriesByLedger[ledger.id] ?? []
        
        // 取引コピー
        if copyTransactions {
            for tx in dataStore.transactions {
                // あなたの Transaction モデルに合わせて調整
                let amount = tx.amount
                let date   = tx.date
                let memo   = tx.memo
                
                let personalCategory = dataStore.categories.first(where: { $0.id == tx.categoryId })
                
                let sharedCategory: SharedCategory? = {
                    guard let p = personalCategory else { return nil }
                    return sharedCategories.first(where: { $0.name == p.name })
                }()
                
                let sharedType: SharedTransactionType = {
                    switch tx.type {
                    case .expense: return .expense
                    case .income:  return .income
                    }
                }()
                
                await addTransaction(
                    to: ledger,
                    amount: amount,
                    date: date,
                    type: sharedType,
                    memo: memo,
                    category: sharedCategory
                )
                incrementCopyDone()
            }
        }
        
        // 最後に進捗をリセット（少し残したければここでフラグだけ変えるなど）
        activeCopy = nil
    }
    
    private func incrementCopyDone() {
        guard var state = activeCopy else { return }
        state.done += 1
        activeCopy = state
    }
    
    /// 指定した共有家計簿用の CKShare を用意して返す
    /// 既に share がある場合はそれを再利用、無ければ新規作成する
    func prepareShare(for ledger: SharedLedger) async throws -> SharePayload {
        // ルートレコードを取得
        let rootRecord = try await db.record(for: ledger.id)
        
        // すでに共有設定済みなら share を再利用
        if let shareRef = rootRecord.share {                        // ← 型: CKRecord.Reference
            let shareRecord = try await db.record(for: shareRef.recordID)
            guard let share = shareRecord as? CKShare else {
                throw NSError(
                    domain: "SharedLedgerStore",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "既存の共有情報を取得できませんでした。"]
                )
            }
            return SharePayload(share: share, rootRecord: rootRecord)
        }
        
        // 新しい share を作成
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = ledger.name as CKRecordValue
        
        // レコードと share を一緒に保存
        let result = try await db.modifyRecords(
            saving: [rootRecord, share],
            deleting: []
        )
        
        // saveResults から CKShare だけを取り出す
        let savedShares: [CKShare] = result.saveResults.compactMap { (_, res) in
            switch res {
            case .success(let record):
                return record as? CKShare
            case .failure:
                return nil
            }
        }
        
        let finalShare = savedShares.first ?? share
        return SharePayload(share: finalShare, rootRecord: rootRecord)
    }
        
    /// 個人用家計簿の全カテゴリを共有家計簿にコピー
    func copyAllCategories(from dataStore: DataStore, to ledger: SharedLedger) async {
        // すでに共有側にあるカテゴリ
        let existing = categoriesByLedger[ledger.id] ?? []
        
        for cat in dataStore.categories {
            // ここはあなたの Category モデルに合わせてプロパティ名を調整してね
            // 例: Category(name: String, icon: String, colorHex: String?)
            let name = cat.name
            let icon = cat.symbolName
            let colorHex = cat.colorHex
            
            // 名前が同じカテゴリはスキップ（重複回避）
            if existing.contains(where: { $0.name == name }) {
                continue
            }
            
            _ = await createCategory(
                for: ledger,
                name: name,
                colorHex: colorHex,
                icon: icon
            )
        }
    }
    
    /// 個人用家計簿の全取引を共有家計簿にコピー
    func copyAllTransactions(from dataStore: DataStore, to ledger: SharedLedger) async {
        // 共有側のカテゴリ一覧（名前ベースで紐付け用）
        let sharedCategories = categoriesByLedger[ledger.id] ?? []
        
        for tx in dataStore.transactions {
            // ここもあなたの Transaction モデルに合わせて調整してね
            // 例: Transaction(amount: Int, date: Date, type: TransactionType, memo: String?, categoryId: UUID)
            let amount = tx.amount
            let date   = tx.date
            let memo   = tx.memo
            
            // 個人側カテゴリを引き当て（ID -> name）
            let personalCategory = dataStore.categories.first(where: { $0.id == tx.categoryId })
            
            // 共有側カテゴリは「同じ名前」で探す
            let sharedCategory: SharedCategory? = {
                guard let p = personalCategory else { return nil }
                return sharedCategories.first(where: { $0.name == p.name })
            }()
            
            // TransactionType -> SharedTransactionType のマッピング
            let sharedType: SharedTransactionType = {
                switch tx.type {
                case .expense: return .expense
                case .income:  return .income
                }
            }()
            
            await addTransaction(
                to: ledger,
                amount: amount,
                date: date,
                type: sharedType,
                memo: memo,
                category: sharedCategory
            )
        }
    }
}
