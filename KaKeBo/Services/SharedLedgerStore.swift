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
    @Published var frequentTemplatesByLedger: [CKRecord.ID: [SharedFrequentTransactionTemplate]] = [:]
    @Published var isLoading = false
    @Published var lastError: Error?

    @Published var activeCopy: CopyState? = nil
    @Published var globalToast: ToastState? = nil
    @Published var deletingLedgerIDs: Set<CKRecord.ID> = []
    
    private let container: CKContainer
    private let db: CKDatabase          // 自分の private DB
    private let sharedDB: CKDatabase    // 共有で見える DB
    private var currentUserRecordName: String?
    
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

    struct ToastState: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let systemImage: String
        let actionTitle: String?
        let action: (() -> Void)?

        static func == (lhs: ToastState, rhs: ToastState) -> Bool {
            lhs.id == rhs.id &&
            lhs.message == rhs.message &&
            lhs.systemImage == rhs.systemImage &&
            lhs.actionTitle == rhs.actionTitle
        }
    }
    
    private var ledgerSourceMap: [CKRecord.ID: LedgerSource] = [:]
    private let defaults = UserDefaults.appGroup
    private var toastTask: Task<Void, Never>?
    private var lastFailedShareMetadata: CKShare.Metadata?
    private let privateSubscriptionID = "kakebo.sharedLedger.privateChanges"
    private let sharedSubscriptionID = "kakebo.sharedLedger.sharedChanges"

    init(container: CKContainer = .default()) {
        self.container = container
        self.db = container.privateCloudDatabase
        self.sharedDB = container.sharedCloudDatabase

        defaults.migrateIfNeeded(keys: [lastOpenedLedgerKey])

        Task {
            await self.configureSharingInfrastructure()
        }
    }

    private let lastOpenedLedgerKey = "LastOpenedSharedLedgerRecordName"
    private let sharedFrequentTemplatesKeyPrefix = "kakebo.shared.frequent.transactions."

    private func frequentTemplatesKey(for ledger: SharedLedger) -> String {
        sharedFrequentTemplatesKeyPrefix + ledger.id.recordName
    }
    
    // 最後に開いた家計簿を記録
    func rememberLastOpened(ledger: SharedLedger) {
        defaults.set(ledger.id.recordName, forKey: lastOpenedLedgerKey)
    }
    
    // 現在の ledgers から、最後に開いた家計簿を探す
    func findLastOpenedLedger() -> SharedLedger? {
        guard let recordName = defaults.string(forKey: lastOpenedLedgerKey) else {
            return nil
        }
        return ledgers.first { $0.id.recordName == recordName }
    }
    
    // MARK: - Helper

    private func currentUserId() async throws -> String {
        let user = try await container.userRecordID()
        currentUserRecordName = user.recordName
        return user.recordName
    }

    private func ensureSharedZone() async throws {
        let zoneID = SharedLedger.zoneID
        do {
            let zones = try await db.recordZones(for: [zoneID])
            if let result = zones[zoneID],
               case .success = result {
                return
            }
        } catch {
            if let ckError = error as? CKError, ckError.code != .zoneNotFound {
                throw error
            }
        }

        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await db.modifyRecordZones(saving: [zone], deleting: [])
    }

    private func configureSharingInfrastructure() async {
        do {
            try await ensureSharedZone()
            try await ensureDatabaseSubscription(id: privateSubscriptionID, in: db)
            try await ensureDatabaseSubscription(id: sharedSubscriptionID, in: sharedDB)
        } catch {
            print("❌ [SharedLedgerStore] configureSharingInfrastructure failed: \(error)")
        }
    }

    private func ensureDatabaseSubscription(id: String, in database: CKDatabase) async throws {
        do {
            _ = try await database.subscription(for: id)
            return
        } catch {
            if let ckError = error as? CKError, ckError.code != .unknownItem {
                throw error
            }
        }

        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        _ = try await database.save(subscription)
    }

    private func queryRecords(
        _ query: CKQuery,
        in db: CKDatabase,
        zoneID: CKRecordZone.ID? = nil
    ) async throws -> [CKRecord] {
        
        var allRecords: [CKRecord] = []
        
        let resolvedZoneID: CKRecordZone.ID? = {
            if let zoneID { return zoneID }
            if db.databaseScope == .private { return SharedLedger.zoneID }
            return nil
        }()
        
        func append(from matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)]) {
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    allRecords.append(record)
                }
            }
        }
        
        if db.databaseScope == .shared {
            // async を直接使う
            let zones: [CKRecordZone]
            if let resolvedZoneID {
                zones = [CKRecordZone(zoneID: resolvedZoneID)]
            } else {
                zones = try await db.allRecordZones()
            }
            
            for zone in zones {
                var current = try await db.records(
                    matching: query,
                    inZoneWith: zone.zoneID,
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
        } else {
            // private / public
            var current = try await db.records(
                matching: query,
                inZoneWith: resolvedZoneID,
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
    
    func acceptShare(_ metadata: CKShare.Metadata) async {
        do {
            let targetContainer = CKContainer(identifier: metadata.containerIdentifier)
            print("🔗 [SharedLedgerStore] Accepting share: container=\(metadata.containerIdentifier)")
            try await acceptShareMetadata(metadata, container: targetContainer)
            lastFailedShareMetadata = nil
            let reloadSucceeded = await reloadLedgers(logContext: "acceptShare success")
            if reloadSucceeded {
                globalToast = ToastState(
                    message: "共有家計簿に参加しました。",
                    systemImage: "person.2.fill",
                    actionTitle: nil,
                    action: nil
                )
            } else {
                globalToast = ToastState(
                    message: "参加は完了しましたが一覧の更新に失敗しました。再度お試しください。",
                    systemImage: "exclamationmark.triangle.fill",
                    actionTitle: "再読み込み",
                    action: { [weak self] in
                        Task { await self?.reloadLedgers(logContext: "acceptShare retry reload") }
                    }
                )
            }
        } catch {
            if let ckError = error as? CKError, isAlreadyParticipantError(ckError) {
                let reloadSucceeded = await reloadLedgers(logContext: "acceptShare alreadyParticipant")
                if reloadSucceeded {
                    globalToast = ToastState(
                        message: "すでにこの共有家計簿に参加しています。",
                        systemImage: "person.2.fill",
                        actionTitle: nil,
                        action: nil
                    )
                } else {
                    globalToast = ToastState(
                        message: "参加済みですが一覧の更新に失敗しました。再度お試しください。",
                        systemImage: "exclamationmark.triangle.fill",
                        actionTitle: "再読み込み",
                        action: { [weak self] in
                            Task { await self?.reloadLedgers(logContext: "acceptShare alreadyParticipant retry reload") }
                        }
                    )
                }
                return
            }

            lastFailedShareMetadata = metadata
            lastError = error
            let retryable = isRetryableShareError(error)
            let actionTitle = retryable ? "再試行" : nil
            let action: (() -> Void)? = retryable ? { [weak self] in
                guard let self else { return }
                Task { await self.acceptShare(metadata) }
            } : nil
            globalToast = ToastState(
                message: "共有家計簿の参加に失敗しました。",
                systemImage: "exclamationmark.triangle.fill",
                actionTitle: actionTitle,
                action: action
            )
            print("❌ [SharedLedgerStore] acceptShare error: \(error)")
        }
    }

    private func acceptShareMetadata(
        _ metadata: CKShare.Metadata,
        container: CKContainer
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.qualityOfService = .userInitiated
            var firstError: Error?
            operation.perShareResultBlock = { meta, result in
                let prefix = "🔍 [SharedLedgerStore] perShareResult"
                if case .failure(let error) = result, firstError == nil {
                    firstError = error
                    if let ckError = error as? CKError {
                        print("\(prefix) failed code=\(ckError.code.rawValue), userInfo=\(ckError.userInfo)")
                    } else {
                        print("\(prefix) failed error=\(error)")
                    }
                } else if case .success = result {
                    print("\(prefix) succeeded")
                }
            }
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    print("✅ [SharedLedgerStore] acceptSharesResult succeeded")
                    if let error = firstError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                case .failure(let error):
                    if let ckError = error as? CKError {
                        print("❌ [SharedLedgerStore] acceptSharesResult failed code=\(ckError.code.rawValue), userInfo=\(ckError.userInfo)")
                    } else {
                        print("❌ [SharedLedgerStore] acceptSharesResult failed error=\(error)")
                    }
                    continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    private func isAlreadyParticipantError(_ error: CKError) -> Bool {
        if error.code == .alreadyShared {
            return true
        }

        guard error.code == .partialFailure,
              let partials = error.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error]
        else {
            return false
        }

        return partials.values.contains {
            guard let ckError = $0 as? CKError else { return false }
            return ckError.code == .alreadyShared
        }
    }

    private func isRetryableShareError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .limitExceeded, .resultsTruncated:
            return true
        default:
            return false
        }
    }

    @discardableResult
    func reloadLedgers(logContext: String? = nil) async -> Bool {
        isLoading = true
        defer { isLoading = false }
        
        let contextPrefix = logContext.map { "[SharedLedgerStore] reloadLedgers(\($0))" } ?? "[SharedLedgerStore] reloadLedgers"
        print("ℹ️ \(contextPrefix) start")

        do {
            let userId = try await currentUserId()
            
            // ① 自分が owner の Ledger（privateDB）
            let owned: [SharedLedger]
            do {
                owned = try await fetchOwnedLedgers(for: userId)
                print("✅ \(contextPrefix) owned count=\(owned.count)")
            } catch {
                print("❌ \(contextPrefix) owned fetch failed: \(error)")
                throw error
            }
            let ownedIDs = Set(owned.map(\.id))
            
            // ② 自分に共有されている Ledger（sharedDB）
            let shared: [SharedLedger]
            do {
                shared = try await fetchSharedLedgers(excluding: ownedIDs)
                print("✅ \(contextPrefix) shared count=\(shared.count)")
            } catch {
                print("❌ \(contextPrefix) shared fetch failed: \(error)")
                throw error
            }
            
            // ③ マージして createdAt でソート
            let all = (owned + shared).sorted(by: { $0.createdAt < $1.createdAt })
            self.ledgers = all
            print("ℹ️ \(contextPrefix) merged total=\(all.count)")
            if shared.isEmpty {
                print("⚠️ \(contextPrefix) shared list is empty")
            }
            return true
            
        } catch {
            self.lastError = error
            print("❌ \(contextPrefix) error:", error)
            return false
        }
    }

    func handleRemoteChange() async {
        let existing = ledgers
        let reloadSucceeded = await reloadLedgers(logContext: "remoteChange")
        let targets = reloadSucceeded ? ledgers : existing
        await refreshCachedRecords(for: targets)
    }

    private func refreshCachedRecords(for ledgers: [SharedLedger]) async {
        guard !ledgers.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for ledger in ledgers {
                group.addTask { [weak self] in
                    await self?.reloadCategories(for: ledger)
                }
                group.addTask { [weak self] in
                    await self?.reloadTransactions(for: ledger)
                }
            }
        }
    }

    // MARK: - よく使う取引（共有家計簿）
    func loadFrequentTemplates(for ledger: SharedLedger) {
        let key = frequentTemplatesKey(for: ledger)
        let data = defaults.migratedData(forKey: key) ?? Data()
        let decoded = (try? JSONDecoder().decode([SharedFrequentTransactionTemplate].self, from: data)) ?? []
        frequentTemplatesByLedger[ledger.id] = decoded
    }

    func addFrequentTemplate(_ tpl: SharedFrequentTransactionTemplate, for ledger: SharedLedger) {
        var templates = frequentTemplatesByLedger[ledger.id] ?? []
        if let idx = templates.firstIndex(where: { $0.isEquivalent(to: tpl) }) {
            templates[idx] = tpl
        } else {
            templates.insert(tpl, at: 0)
        }
        frequentTemplatesByLedger[ledger.id] = templates
        saveFrequentTemplates(for: ledger, templates: templates)
    }

    func deleteFrequentTemplate(id: UUID, in ledger: SharedLedger) {
        var templates = frequentTemplatesByLedger[ledger.id] ?? []
        templates.removeAll { $0.id == id }
        frequentTemplatesByLedger[ledger.id] = templates
        saveFrequentTemplates(for: ledger, templates: templates)
    }

    func moveFrequentTemplates(for ledger: SharedLedger, from offsets: IndexSet, to destination: Int) {
        var templates = frequentTemplatesByLedger[ledger.id] ?? []
        templates.move(fromOffsets: offsets, toOffset: destination)
        frequentTemplatesByLedger[ledger.id] = templates
        saveFrequentTemplates(for: ledger, templates: templates)
    }

    private func saveFrequentTemplates(for ledger: SharedLedger, templates: [SharedFrequentTransactionTemplate]) {
        defaults.set(try? JSONEncoder().encode(templates), forKey: frequentTemplatesKey(for: ledger))
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
            try await ensureSharedZone()
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

            ledgerSourceMap[final.id] = .private

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
    
    @discardableResult
    func deleteLedger(_ ledger: SharedLedger) async -> Bool {
        guard isOwned(ledger) else {
            print("deleteLedger: non-owned ledger, skip")
            return false
        }

        deletingLedgerIDs.insert(ledger.id)

        var removedLedger: SharedLedger?
        var removedIndex: Int?

        if let idx = ledgers.firstIndex(where: { $0.id == ledger.id }) {
            removedLedger = ledgers[idx]
            removedIndex = idx
            _ = withAnimation {
                ledgers.remove(at: idx)
            }
        }

        do {
            try await db.deleteRecord(withID: ledger.id)
            ledgerSourceMap[ledger.id] = nil
            // 必要なら関連トランザクションのキャッシュも削除
            transactionsByLedger[ledger.id] = nil
            categoriesByLedger[ledger.id] = nil
            deletingLedgerIDs.remove(ledger.id)
            showToast(message: "「\(ledger.name)」の削除が完了しました")
            return true
        } catch {
            lastError = error
            if let ledger = removedLedger, let idx = removedIndex {
                ledgers.insert(ledger, at: idx)
            }
            deletingLedgerIDs.remove(ledger.id)
            return false
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

    func deleteTransaction(_ tx: SharedTransaction, from ledger: SharedLedger) async {
        do {
            let targetDB = database(for: ledger)
            try await targetDB.deleteRecord(withID: tx.id)

            if var list = transactionsByLedger[ledger.id] {
                list.removeAll { $0.id == tx.id }
                transactionsByLedger[ledger.id] = list
            }
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
        if let userId = currentUserRecordName, ledger.ownerUserId == userId {
            return true
        }
        return ledgerSourceMap[ledger.id] != .shared
    }
}

extension SharedLedgerStore {
    struct SharePayload: Identifiable {
        let share: CKShare
        let rootRecord: CKRecord

        var id: CKRecord.ID { share.recordID }
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

    func showToast(
        message: String,
        systemImage: String = "checkmark.circle.fill",
        duration: UInt64 = 2_000_000_000
    ) {
        toastTask?.cancel()

        withAnimation {
            globalToast = ToastState(
                message: message,
                systemImage: systemImage,
                actionTitle: nil,
                action: nil
            )
        }

        toastTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: duration)
                withAnimation {
                    globalToast = nil
                }
            } catch {
                // Cancelled
            }
        }
    }
    
    /// 指定した共有家計簿用の CKShare を用意して返す
    /// 既に share がある場合はそれを再利用、無ければ新規作成する
    func prepareShare(for ledger: SharedLedger) async throws -> SharePayload {
        try await ensureSharedZone()
        // ① 常にサーバー側の最新 rootRecord を取得
        let rootRecord = try await db.record(for: ledger.id)
        
        // ② すでに共有設定済みなら share を再利用
        if let shareRef = rootRecord.share {
            let shareRecord = try await db.record(for: shareRef.recordID)
            guard let share = shareRecord as? CKShare else {
                throw NSError(
                    domain: "SharedLedgerStore",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "既存の共有情報を取得できませんでした。"]
                )
            }

            let updatedShare = try await ensureShareIsJoinable(
                share,
                rootRecord: rootRecord,
                ledgerName: ledger.name
            )
            return SharePayload(share: updatedShare, rootRecord: rootRecord)
        }

        // ③ 新しい share を作成（必ず rootRecord を渡す）
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = ledger.name as CKRecordValue
        share.publicPermission = .readWrite

        // ④ root + share を同じ modifyRecords で保存
        var saveResults: [CKRecord.ID: Result<CKRecord, any Error>]
        do {
            (saveResults, _) = try await db.modifyRecords(
                saving: [rootRecord, share],
                deleting: []
            )
        } catch {
            // atomic failure などでまとめて失敗した場合でも、
            // すでにサーバー側で share が作成済みの可能性があるため再取得を試みる
            if let payload = try await fetchExistingSharePayload(for: ledger) {
                return payload
            }

            // プロダクション環境で atomic failure が発生するケースがあったため、
            // 非アトミック & 変更差分のみの保存で再試行する
            if let ckError = error as? CKError, ckError.code == .partialFailure {
                do {
                    (saveResults, _) = try await db.modifyRecords(
                        saving: [rootRecord, share],
                        deleting: [],
                        savePolicy: .changedKeys,
                        atomically: false
                    )
                } catch {
                    throw error
                }
            } else {
                throw error
            }
        }
        
        // ⑤ rootRecord の結果を確認
        let rootResult = saveResults[rootRecord.recordID]
        let savedRoot: CKRecord
        switch rootResult {
        case .success(let record):
            savedRoot = record
        case .failure(let error):
            throw error   // root の保存に失敗してたら即エラーにする
        case .none:
            throw NSError(
                domain: "SharedLedgerStore",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "rootRecord の保存結果が取得できませんでした。"]
            )
        }
        
        // ⑥ share の結果を確認
        let shareResult = saveResults[share.recordID]
        let savedShare: CKShare
        switch shareResult {
        case .success(let record):
            guard let s = record as? CKShare else {
                throw NSError(
                    domain: "SharedLedgerStore",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "保存されたレコードが CKShare ではありません。"]
                )
            }
            let ensuredShare = try await ensureShareIsJoinable(
                s,
                rootRecord: savedRoot,
                ledgerName: ledger.name
            )
            savedShare = ensuredShare
        case .failure(let error):
            throw error    // ← ここで CKError.code12 とかが返ってくる
        case .none:
            throw NSError(
                domain: "SharedLedgerStore",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "share の保存結果が取得できませんでした。"]
            )
        }
        
        // ⑦ 成功したものだけ返す（未保存 share は絶対に返さない）
        return SharePayload(share: savedShare, rootRecord: savedRoot)
    }

    /// 共有情報が既に存在する場合に再利用する
    private func fetchExistingSharePayload(for ledger: SharedLedger) async throws -> SharePayload? {
        let latestRoot = try await db.record(for: ledger.id)
        guard let shareRef = latestRoot.share else { return nil }

        let shareRecord = try await db.record(for: shareRef.recordID)
        guard let share = shareRecord as? CKShare else { return nil }

        let updatedShare = try await ensureShareIsJoinable(
            share,
            rootRecord: latestRoot,
            ledgerName: ledger.name
        )

        return SharePayload(share: updatedShare, rootRecord: latestRoot)
    }

    /// 共有リンクから誰でも参加できるよう、必要な設定が抜けていた場合に補正する
    private func ensureShareIsJoinable(
        _ share: CKShare,
        rootRecord: CKRecord,
        ledgerName: String
    ) async throws -> CKShare {

        var needsSave = false

        if share.publicPermission != .readWrite {
            share.publicPermission = .readWrite
            needsSave = true
        }

        if share[CKShare.SystemFieldKey.title] as? String != ledgerName {
            share[CKShare.SystemFieldKey.title] = ledgerName as CKRecordValue
            needsSave = true
        }

        guard needsSave else { return share }

        let (saveResults, _) = try await db.modifyRecords(
            saving: [rootRecord, share],
            deleting: [],
            savePolicy: .changedKeys
        )

        guard let shareResult = saveResults[share.recordID] else { return share }

        switch shareResult {
        case .success(let record):
            return record as? CKShare ?? share
        case .failure(let error):
            throw error
        }
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

// MARK: - バックアップ（共有家計簿）
extension SharedLedgerStore {
    
    /// 共有家計簿をバックアップファイル（個人用と同じ JSON 形式）としてエクスポート
    func exportBackup(for ledger: SharedLedger) async throws -> Data {
        // 事前に過去のエラーをクリアし、フェッチ失敗を見逃さない
        lastError = nil
        
        await reloadCategories(for: ledger)
        await reloadTransactions(for: ledger)
        
        if let error = lastError {
            throw error
        }
        
        guard
            let categories = categoriesByLedger[ledger.id],
            let transactions = transactionsByLedger[ledger.id]
        else {
            throw NSError(
                domain: "SharedLedgerStore",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "バックアップ用データの取得に失敗しました。ネットワーク接続を確認して再度お試しください。"]
            )
        }
        
        // 共有カテゴリ ID -> バックアップ用 UUID のマップ
        var idMap: [CKRecord.ID: UUID] = [:]
        var backupCategories: [BackupCategory] = []
        for cat in categories {
            let backupId = UUID()
            idMap[cat.id] = backupId
            backupCategories.append(
                .init(
                    id: backupId,
                    name: cat.name,
                    symbolName: cat.icon,
                    colorHex: cat.colorHex
                )
            )
        }
        
        var backupTransactions: [BackupTransaction] = []
        for tx in transactions {
            let backupCategoryId: UUID = {
                if let original = tx.categoryId, let mapped = idMap[original] { return mapped }
                // 取引に紐付くカテゴリが見つからない場合は、新規カテゴリを用意して付与する
                if let existing = backupCategories.first(where: { $0.name == tx.categoryName }) {
                    return existing.id
                } else {
                    let new = BackupCategory(
                        id: UUID(),
                        name: tx.categoryName,
                        symbolName: "tag.fill",
                        colorHex: tx.categoryColorHex
                    )
                    backupCategories.append(new)
                    return new.id
                }
            }()
            
            backupTransactions.append(
                .init(
                    id: UUID(),
                    date: tx.date,
                    amount: tx.amount,
                    typeRaw: tx.type == .income ? "income" : "expense",
                    memo: tx.memo ?? "",
                    categoryId: backupCategoryId,
                    tags: nil
                )
            )
        }
        
        let payload = KaKeBoBackupV1(
            exportedAt: Date(),
            categories: backupCategories,
            transactions: backupTransactions,
            recurringTodos: nil,
            fixedExpenses: nil,
            reminders: nil,
            dayNotes: nil,
            monthStartSettings: nil,
            theme: nil
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }
    
    /// バックアップファイルを共有家計簿へ復元
    func importBackup(data: Data, to ledger: SharedLedger) async throws -> DataStore.ImportReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(KaKeBoBackupV1.self, from: data)
        
        // 事前に最新データを反映
        await reloadCategories(for: ledger)
        await reloadTransactions(for: ledger)
        
        var createdCategories = 0
        var insertedTransactions = 0
        var skippedTransactions = 0
        
        let backupCategoryById = Dictionary(uniqueKeysWithValues: backup.categories.map { ($0.id, $0) })
        var sharedCategories = categoriesByLedger[ledger.id] ?? []
        
        // バックアップ ID -> 共有カテゴリ ID
        var categoryIdMap: [UUID: CKRecord.ID] = [:]
        
        // 既存カテゴリがあればマッピング、なければ新規作成
        for bc in backup.categories {
            if let existing = sharedCategories.first(where: { $0.name == bc.name }) {
                categoryIdMap[bc.id] = existing.id
            } else if let created = await createCategory(
                for: ledger,
                name: bc.name,
                colorHex: bc.colorHex,
                icon: bc.symbolName
            ) {
                categoryIdMap[bc.id] = created.id
                createdCategories += 1
                sharedCategories.append(created)
            }
        }
        
        // 作成/更新後のカテゴリキャッシュを最新化
        await reloadCategories(for: ledger)
        sharedCategories = categoriesByLedger[ledger.id] ?? sharedCategories
        var categoryById = Dictionary(uniqueKeysWithValues: sharedCategories.map { ($0.id, $0) })
        var categoryByName = Dictionary(uniqueKeysWithValues: sharedCategories.map { ($0.name, $0) })
        
        // 既存取引との重複チェック用
        let existingTransactions = transactionsByLedger[ledger.id] ?? []
        let calendar = Calendar.current
        
        func resolveCategory(for backupId: UUID) async -> SharedCategory? {
            if let mappedId = categoryIdMap[backupId], let cat = categoryById[mappedId] {
                return cat
            }
            guard let backupCategory = backupCategoryById[backupId] else { return nil }
            if let existing = categoryByName[backupCategory.name] {
                categoryIdMap[backupCategory.id] = existing.id
                return existing
            }
            if let created = await createCategory(
                for: ledger,
                name: backupCategory.name,
                colorHex: backupCategory.colorHex,
                icon: backupCategory.symbolName
            ) {
                categoryIdMap[backupCategory.id] = created.id
                categoryById[created.id] = created
                categoryByName[created.name] = created
                createdCategories += 1
                return created
            }
            return nil
        }
        
        for bt in backup.transactions {
            // 既存の重複（同日/金額/メモ一致）を除外
            let memo = bt.memo
            if existingTransactions.contains(where: {
                calendar.isDate($0.date, inSameDayAs: bt.date) &&
                $0.amount == bt.amount &&
                ($0.memo ?? "") == memo
            }) {
                skippedTransactions += 1
                continue
            }
            
            let category = await resolveCategory(for: bt.categoryId)
            let sharedType: SharedTransactionType = bt.typeRaw == "income" ? .income : .expense
            
            await addTransaction(
                to: ledger,
                amount: bt.amount,
                date: bt.date,
                type: sharedType,
                memo: memo,
                category: category
            )
            insertedTransactions += 1
        }
        
        return .init(inserted: insertedTransactions, createdCategories: createdCategories, skipped: skippedTransactions)
    }
}
