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
    enum ShareAcceptResult {
        case joined
        case alreadyJoined
        case pending
        case failed
    }

    @Published var ledgers: [SharedLedger] = []
    @Published var transactionsByLedger: [CKRecord.ID: [SharedTransaction]] = [:]
    @Published var categoriesByLedger: [CKRecord.ID: [SharedCategory]] = [:]
    @Published var frequentTemplatesByLedger: [CKRecord.ID: [SharedFrequentTransactionTemplate]] = [:]
    @Published var isLoading = false
    @Published var lastError: Error?
    /// 共有家計簿の読み込みに失敗（iCloud不可・通信エラー・一時的な空振り等）したかどうか。
    /// 一覧が空表示になる前にエラーを可視化し、キャッシュ表示＋再試行へ誘導するために使う。
    @Published var loadFailed = false

    @Published var activeCopy: CopyState? = nil
    @Published var globalToast: ToastState? = nil
    @Published var isAcceptingShare = false
    @Published var lastAcceptedLedgerID: CKRecord.ID?
    @Published var deletingLedgerIDs: Set<CKRecord.ID> = []
    
    private let container: CKContainer
    private let db: CKDatabase          // 自分の private DB
    private let sharedDB: CKDatabase    // 共有で見える DB
    private var currentUserRecordName: String?
    
    enum LedgerSource {
        case `private`
        case shared

        var databaseLabel: String {
            switch self {
            case .private: return "privateCloudDatabase"
            case .shared: return "sharedCloudDatabase"
            }
        }
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
    /// 友達招待プレミアム体験を付与するための課金マネージャ参照（KaKeBoApp で注入）
    weak var purchaseManager: PurchaseManager?
    /// 招待報酬チェックのスロットリング用
    private var lastReferralCheck: Date?
    private var lastFailedShareMetadata: CKShare.Metadata?
    private var shareAcceptanceRetryTasks: [String: Task<Void, Never>] = [:]
    private var shareAcceptanceRetryCounts: [String: Int] = [:]
    private let maxShareAcceptanceRetryCount = 6
    private let privateSubscriptionID = "kakebo.sharedLedger.privateChanges"
    private let sharedSubscriptionID = "kakebo.sharedLedger.sharedChanges"

    init(container: CKContainer = .default()) {
        self.container = container
        self.db = container.privateCloudDatabase
        self.sharedDB = container.sharedCloudDatabase

        defaults.migrateIfNeeded(keys: [lastOpenedLedgerKey])

        // 前回取得できた共有家計簿一覧をローカルから即時復元（CloudKit取得失敗時の「全消え」防止）
        loadLedgerCache()

        Task {
            await self.configureSharingInfrastructure()
        }
    }

    // MARK: - 共有家計簿一覧のローカルキャッシュ（読み込み失敗時の保険）

    private let ledgerCacheKey = "sharedLedger.cachedList.v1"

    /// 一覧キャッシュ用の Codable 表現（CKRecord.ID を分解して保存）
    private struct CachedLedger: Codable {
        let recordName: String
        let zoneName: String
        let zoneOwnerName: String
        let name: String
        let icon: String
        let colorHex: String
        let ownerUserId: String
        let createdAt: Date
        let updatedAt: Date
        let isOwned: Bool

        init(ledger: SharedLedger, isOwned: Bool) {
            self.recordName = ledger.id.recordName
            self.zoneName = ledger.id.zoneID.zoneName
            self.zoneOwnerName = ledger.id.zoneID.ownerName
            self.name = ledger.name
            self.icon = ledger.icon
            self.colorHex = ledger.colorHex
            self.ownerUserId = ledger.ownerUserId
            self.createdAt = ledger.createdAt
            self.updatedAt = ledger.updatedAt
            self.isOwned = isOwned
        }

        var ledger: SharedLedger {
            let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
            let recordID = CKRecord.ID(recordName: recordName, zoneID: zoneID)
            return SharedLedger(
                id: recordID,
                name: name,
                icon: icon,
                colorHex: colorHex,
                ownerUserId: ownerUserId,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    /// 現在の一覧をローカルへ保存する
    private func saveLedgerCache() {
        let cached = ledgers.map { CachedLedger(ledger: $0, isOwned: ledgerSourceMap[$0.id] != .shared) }
        defaults.set(try? JSONEncoder().encode(cached), forKey: ledgerCacheKey)
    }

    /// ローカルキャッシュから一覧を復元する（CloudKit取得前の即時表示用）
    private func loadLedgerCache() {
        guard
            let data = defaults.data(forKey: ledgerCacheKey),
            let cached = try? JSONDecoder().decode([CachedLedger].self, from: data),
            !cached.isEmpty
        else { return }
        ledgers = cached.map(\.ledger)
        for item in cached {
            ledgerSourceMap[item.ledger.id] = item.isOwned ? .private : .shared
        }
        print("ℹ️ [SharedLedgerStore] restored \(cached.count) ledgers from local cache")
    }

    // MARK: - 自動リトライ（指数バックオフ）

    private var reloadRetryTask: Task<Void, Never>?
    private var reloadRetryCount = 0
    private let maxReloadRetry = 5

    /// 読み込み失敗時に、指数バックオフで自動リトライを仕込む
    private func scheduleAutoReloadRetry() {
        guard reloadRetryCount < maxReloadRetry else { return }
        reloadRetryTask?.cancel()
        let attempt = reloadRetryCount
        reloadRetryTask = Task { [weak self] in
            // 2,4,8,16,30 秒（上限30秒）
            let seconds = min(30, 1 << (attempt + 1))
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            self.reloadRetryCount += 1
            _ = await self.reloadLedgers(logContext: "autoRetry#\(self.reloadRetryCount)")
        }
    }

    private func resetReloadRetry() {
        reloadRetryCount = 0
        reloadRetryTask?.cancel()
        reloadRetryTask = nil
    }

    private let lastOpenedLedgerKey = "LastOpenedSharedLedgerRecordName"
    private let sharedFrequentTemplatesKeyPrefix = "kakebo.shared.frequent.transactions."

    var ownedLedgers: [SharedLedger] {
        ledgers.filter { ledgerSourceMap[$0.id] != .shared }
    }

    var participatingLedgers: [SharedLedger] {
        ledgers.filter { ledgerSourceMap[$0.id] == .shared }
    }

    func source(for ledger: SharedLedger) -> LedgerSource {
        if let source = ledgerSourceMap[ledger.id] {
            return source
        }
        if let currentUserRecordName, ledger.ownerUserId != currentUserRecordName {
            return .shared
        }
        return .private
    }

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
    

    @discardableResult
    func acceptShareURL(_ url: URL) async -> ShareAcceptResult {
        print("ℹ️ [SharedLedgerStore] acceptShareURL start url=\(url.absoluteString)")
        do {
            let metadata = try await CKContainer.default().shareMetadata(for: url)
            print("ℹ️ [SharedLedgerStore] shareMetadata resolved via URL container=\(metadata.containerIdentifier), shareID=\(metadata.share.recordID.recordName)")
            return await acceptShare(metadata)
        } catch {
            lastError = error
            globalToast = ToastState(
                message: "リンクの読み込みに失敗しました。Safariでリンクを開くか、リンク全体をコピーしてもう一度お試しください。",
                systemImage: "exclamationmark.triangle.fill",
                actionTitle: nil,
                action: nil
            )
            print("❌ [SharedLedgerStore] acceptShareURL error url=\(url.absoluteString), error=\(error)")
            return .failed
        }
    }

    @discardableResult
    func acceptShare(_ metadata: CKShare.Metadata) async -> ShareAcceptResult {
        isAcceptingShare = true
        defer { isAcceptingShare = false }

        let shareID = metadata.share.recordID.recordName
        print("ℹ️ [SharedLedgerStore] acceptShare start container=\(metadata.containerIdentifier), shareID=\(shareID)")
        // NOTE:
        // CKShare.Metadata.rootRecordID は iOS 16 で deprecated のため参照しない。
        // 参加結果は「受諾成功後に一覧へ新規追加されたか」と CloudKit のエラー種別で判定する。
        let previousLedgerIDs = Set(ledgers.map(\.id))

        do {
            let targetContainer = CKContainer(identifier: metadata.containerIdentifier)
            print("🔗 [SharedLedgerStore] Accepting share: container=\(metadata.containerIdentifier), shareID=\(shareID)")
            try await acceptShareMetadata(metadata, container: targetContainer)
            lastFailedShareMetadata = nil
            lastError = nil
            clearShareAcceptanceRetryState(shareID: shareID)
            let reloadSucceeded = await reloadLedgers(logContext: "acceptShare success")
            if reloadSucceeded {
                await refreshCachedRecords(for: ledgers)
            }
            let addedLedger = ledgers.first(where: { !previousLedgerIDs.contains($0.id) })
            if let addedLedger {
                lastAcceptedLedgerID = addedLedger.id
                rememberLastOpened(ledger: addedLedger)
                print("✅ [SharedLedgerStore] accepted ledger detected id=\(addedLedger.id.recordName)")
            }
            if reloadSucceeded, addedLedger != nil {
                globalToast = ToastState(
                    message: "共有家計簿に参加しました。",
                    systemImage: "person.2.fill",
                    actionTitle: nil,
                    action: nil
                )
                return .joined
            } else if reloadSucceeded {
                globalToast = ToastState(
                    message: "参加処理を受け付けました。反映に少し時間がかかる場合があります。",
                    systemImage: "clock.badge.exclamationmark",
                    actionTitle: "再読み込み",
                    action: { [weak self] in
                        Task { await self?.reloadLedgers(logContext: "acceptShare delayed reload") }
                    }
                )
                return .pending
            } else {
                globalToast = ToastState(
                    message: "参加は完了しましたが一覧の更新に失敗しました。再度お試しください。",
                    systemImage: "exclamationmark.triangle.fill",
                    actionTitle: "再読み込み",
                    action: { [weak self] in
                        Task { await self?.reloadLedgers(logContext: "acceptShare retry reload") }
                    }
                )
                return .pending
            }
        } catch {
            if let ckError = error as? CKError, isAlreadyParticipantError(ckError) {
                clearShareAcceptanceRetryState(shareID: shareID)
                let reloadSucceeded = await reloadLedgers(logContext: "acceptShare alreadyParticipant")
                if reloadSucceeded {
                    await refreshCachedRecords(for: ledgers)
                }
                lastError = nil
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
                return .alreadyJoined
            }

            if let ckError = error as? CKError, ckError.code == .quotaExceeded {
                let recovered = await fallbackReloadAfterAcceptanceIssue(
                    metadata,
                    beforeLedgerIDs: previousLedgerIDs
                )
                if recovered {
                    lastError = nil
                    clearShareAcceptanceRetryState(shareID: shareID)
                    globalToast = ToastState(
                        message: "共有家計簿の同期に時間がかかっています。しばらくしてから内容が表示されます。",
                        systemImage: "clock.badge.exclamationmark",
                        actionTitle: nil,
                        action: nil
                    )
                    return .pending
                }
                scheduleShareAcceptanceRetryIfNeeded(
                    metadata: metadata,
                    retryAfter: retryAfterSeconds(from: ckError)
                )
                lastError = nil
                return .pending
            }

            lastFailedShareMetadata = metadata
            lastError = error
            let retryable = isRetryableShareError(error)
            let friendlyMessage = shareAcceptanceErrorMessage(for: error)
            let canRetryImmediately = canRetryImmediately(for: error)
            let actionTitle = retryable && canRetryImmediately ? "再試行" : nil
            let action: (() -> Void)? = retryable && canRetryImmediately ? { [weak self] in
                guard let self else { return }
                Task { await self.acceptShare(metadata) }
            } : nil
            globalToast = ToastState(
                message: friendlyMessage,
                systemImage: "exclamationmark.triangle.fill",
                actionTitle: actionTitle,
                action: action
            )
            if let ckError = error as? CKError {
                presentQuotaExceededToast(
                    operation: "acceptShare",
                    containerIdentifier: metadata.containerIdentifier,
                    shareID: shareID,
                    ledgerID: nil,
                    error: ckError
                )
            }
            if let ckError = error as? CKError,
               let retryAfter = retryAfterSeconds(from: ckError) {
                print("❌ [SharedLedgerStore] acceptShare error container=\(metadata.containerIdentifier), shareID=\(shareID), retryAfter=\(retryAfter), error=\(error)")
            } else {
                print("❌ [SharedLedgerStore] acceptShare error container=\(metadata.containerIdentifier), shareID=\(shareID), error=\(error)")
            }
            return .failed
        }
    }

    private func acceptShareMetadata(
        _ metadata: CKShare.Metadata,
        container: CKContainer
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
            operation.qualityOfService = .userInitiated
            var perShareErrors: [String: Error] = [:]
            operation.perShareResultBlock = { meta, result in
                let prefix = "🔍 [SharedLedgerStore] perShareResult"
                if case .failure(let error) = result {
                    perShareErrors[meta.share.recordID.recordName] = error
                    if let ckError = error as? CKError {
                        print("\(prefix) failed container=\(meta.containerIdentifier), shareID=\(meta.share.recordID.recordName), code=\(ckError.code.rawValue), userInfo=\(ckError.userInfo)")
                    } else {
                        print("\(prefix) failed container=\(meta.containerIdentifier), shareID=\(meta.share.recordID.recordName), error=\(error)")
                    }
                } else if case .success = result {
                    print("\(prefix) succeeded container=\(meta.containerIdentifier), shareID=\(meta.share.recordID.recordName)")
                }
            }
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success:
                    print("✅ [SharedLedgerStore] acceptSharesResult succeeded")
                    if !perShareErrors.isEmpty {
                        let quotaError = perShareErrors.values
                            .compactMap { $0 as? CKError }
                            .first(where: { $0.code == .quotaExceeded })
                        if let quotaError {
                            print("⚠️ [SharedLedgerStore] acceptSharesResult succeeded with perShare quotaExceeded. continue as success and reload from shared DB.")
                            continuation.resume(throwing: quotaError)
                        } else {
                            print("⚠️ [SharedLedgerStore] acceptSharesResult succeeded with perShare errors. continue as success and rely on reload.")
                            if let firstError = perShareErrors.values.first {
                                continuation.resume(throwing: firstError)
                            } else {
                                continuation.resume()
                            }
                        }
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

        if error.code == .serverRecordChanged {
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

    private func fallbackReloadAfterAcceptanceIssue(
        _ metadata: CKShare.Metadata,
        beforeLedgerIDs: Set<CKRecord.ID>
    ) async -> Bool {
        let reloadSucceeded = await reloadLedgers(logContext: "acceptShare fallbackReload")
        if reloadSucceeded {
            await refreshCachedRecords(for: ledgers)
        }

        let acceptedShareID = metadata.share.recordID.recordName
        if let matched = ledgers.first(where: { !beforeLedgerIDs.contains($0.id) }) {
            lastAcceptedLedgerID = matched.id
            rememberLastOpened(ledger: matched)
            print("✅ [SharedLedgerStore] fallbackReload matched ledger id=\(matched.id.recordName), shareID=\(acceptedShareID)")
            return true
        }
        return false
    }

    private func scheduleShareAcceptanceRetryIfNeeded(
        metadata: CKShare.Metadata,
        retryAfter: TimeInterval?
    ) {
        let shareID = metadata.share.recordID.recordName
        let attempts = shareAcceptanceRetryCounts[shareID] ?? 0
        guard attempts < maxShareAcceptanceRetryCount else {
            print("⚠️ [SharedLedgerStore] skip auto-retry shareID=\(shareID) reason=maxAttempts(\(maxShareAcceptanceRetryCount))")
            globalToast = ToastState(
                message: "参加処理が完了できませんでした。招待した人のiCloud空き容量を確認してから、もう一度お試しください。",
                systemImage: "externaldrive.fill.badge.exclamationmark",
                actionTitle: nil,
                action: nil
            )
            return
        }

        shareAcceptanceRetryTasks[shareID]?.cancel()
        shareAcceptanceRetryCounts[shareID] = attempts + 1

        let delay = max(30, Int((retryAfter ?? 120).rounded()))
        print("ℹ️ [SharedLedgerStore] schedule auto-retry shareID=\(shareID), attempt=\(attempts + 1), delay=\(delay)s")

        globalToast = ToastState(
            message: "参加処理に時間がかかっています。約\(formattedRetryText(seconds: TimeInterval(delay)))後に自動で再試行します。招待した人のiCloud空き容量が不足していると完了しない場合があります。",
            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            actionTitle: nil,
            action: nil
        )

        shareAcceptanceRetryTasks[shareID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.acceptShare(metadata)
        }
    }

    private func clearShareAcceptanceRetryState(shareID: String) {
        shareAcceptanceRetryTasks[shareID]?.cancel()
        shareAcceptanceRetryTasks[shareID] = nil
        shareAcceptanceRetryCounts[shareID] = nil
    }

    private func isRetryableShareError(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy, .limitExceeded, .resultsTruncated, .quotaExceeded:
            return true
        default:
            return false
        }
    }

    private func canRetryImmediately(for error: Error) -> Bool {
        guard let ckError = error as? CKError else { return true }
        if ckError.code == .quotaExceeded { return false }
        if ckError.code == .requestRateLimited,
           retryAfterSeconds(from: ckError) != nil {
            return false
        }
        return true
    }

    private func retryAfterSeconds(from ckError: CKError) -> TimeInterval? {
        if let seconds = ckError.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            return seconds
        }
        if let seconds = ckError.userInfo[CKErrorRetryAfterKey] as? NSNumber {
            return seconds.doubleValue
        }
        return nil
    }

    private func formattedRetryText(seconds: TimeInterval) -> String {
        let rounded = max(1, Int(seconds.rounded()))
        if rounded < 60 {
            return "\(rounded)秒"
        }
        let minutes = Int(ceil(Double(rounded) / 60.0))
        return "\(minutes)分"
    }

    private func shareAcceptanceErrorMessage(for error: Error) -> String {
        guard let ckError = error as? CKError else {
            return "共有家計簿の参加に失敗しました。時間をおいて再度お試しください。"
        }

        switch ckError.code {
        case .notAuthenticated:
            return "iCloudにサインインしてから、もう一度お試しください。"
        case .permissionFailure:
            return "この共有家計簿に参加する権限がありません。共有リンクの再発行を依頼してください。"
        case .unknownItem:
            return "共有リンクの有効期限が切れているか、すでに無効になっています。新しいリンクをお試しください。"
        case .networkUnavailable, .networkFailure, .serviceUnavailable:
            return "通信が不安定なため参加できませんでした。接続状況を確認して再度お試しください。"
        case .requestRateLimited:
            if let retryAfter = retryAfterSeconds(from: ckError) {
                return "アクセスが集中しています。約\(formattedRetryText(seconds: retryAfter))後にもう一度お試しください。"
            }
            return "アクセスが集中しています。しばらく待ってからもう一度お試しください。"
        case .quotaExceeded:
            if let retryAfter = retryAfterSeconds(from: ckError) {
                return "現在、iCloud側の処理待ちが発生しています。約\(formattedRetryText(seconds: retryAfter))後にもう一度お試しください。招待した人のiCloud空き容量不足でも失敗することがあります。"
            }
            return "現在、iCloud側の処理待ちが発生しています。しばらく待ってからもう一度お試しください。招待した人のiCloud空き容量不足でも失敗することがあります。"
        default:
            return "共有家計簿の参加に失敗しました。LINEなどのアプリ内ブラウザで開いた場合は、Safariで開き直してお試しください。"
        }
    }

    private func presentQuotaExceededToast(
        operation: String,
        containerIdentifier: String,
        shareID: String? = nil,
        ledgerID: CKRecord.ID? = nil,
        error: CKError
    ) {
        guard error.code == .quotaExceeded else { return }

        let retrySuffix: String
        if let retryAfter = retryAfterSeconds(from: error) {
            retrySuffix = " 約\(formattedRetryText(seconds: retryAfter))後に再試行してください。"
        } else {
            retrySuffix = " 少し時間を空けて再試行してください。"
        }

        let ledgerSuffix = ledgerID.map { " ledgerID=\($0.recordName)" } ?? ""
        let shareSuffix = shareID.map { ", shareID=\($0)" } ?? ""

        globalToast = ToastState(
            message: "iCloudの容量上限により処理できませんでした。" + retrySuffix,
            systemImage: "externaldrive.fill.badge.exclamationmark",
            actionTitle: nil,
            action: nil
        )

        print("❌ [SharedLedgerStore] quotaExceeded operation=\(operation), container=\(containerIdentifier)\(shareSuffix)\(ledgerSuffix), retryAfter=\(retryAfterSeconds(from: error)?.description ?? "n/a"), userInfo=\(error.userInfo)")
    }

    /// - Parameter acceptsEmptyResult: 取得結果が空のとき、既存の一覧（キャッシュ）を空で上書きしてよいか。
    ///   ユーザー操作による明示的な再読み込み（プル更新等）では true を渡す。自動・バックグラウンド更新では
    ///   一時的な空振りで「全消え」表示にならないよう false（既定）にする。
    @discardableResult
    func reloadLedgers(logContext: String? = nil, acceptsEmptyResult: Bool = false) async -> Bool {
        isLoading = true
        defer { isLoading = false }

        let contextPrefix = logContext.map { "[SharedLedgerStore] reloadLedgers(\($0))" } ?? "[SharedLedgerStore] reloadLedgers"
        print("ℹ️ \(contextPrefix) start")

        // iCloud アカウント状態を事前チェック（未ログイン時は即座にスキップ）
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                print("⚠️ \(contextPrefix) iCloud unavailable (status=\(status.rawValue)) → スキップ")
                loadFailed = true
                scheduleAutoReloadRetry()
                return false
            }
        } catch {
            print("⚠️ \(contextPrefix) iCloud status check failed: \(error) → スキップ")
            loadFailed = true
            scheduleAutoReloadRetry()
            return false
        }

        do {
            ledgerSourceMap.removeAll()
            let previousIDs = Set(ledgers.map(\.id))
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

            // 空振りガード：取得自体は成功でも結果が空、かつ既存一覧が非空のときは
            // 一時的な不整合（iCloud同期遅延・ゾーン未準備等）の可能性が高い。
            // 既存（キャッシュ）を消さずに保持し、エラー表示＋自動リトライに回す。
            // 本当に0件になるケース（最後の家計簿を脱退/削除）は leaveLedger/deleteLedger 側で
            // 一覧を直接更新するため、ここで空にする必要はない。
            if all.isEmpty && !ledgers.isEmpty && !acceptsEmptyResult {
                print("⚠️ \(contextPrefix) fetched empty but list was non-empty → keep cache & retry")
                loadFailed = true
                scheduleAutoReloadRetry()
                return false
            }

            self.ledgers = all
            saveLedgerCache()
            loadFailed = false
            resetReloadRetry()
            let currentIDs = Set(all.map(\.id))
            let removed = previousIDs.subtracting(currentIDs)
            for removedID in removed {
                transactionsByLedger[removedID] = nil
                categoriesByLedger[removedID] = nil
                frequentTemplatesByLedger[removedID] = nil
            }
            print("ℹ️ \(contextPrefix) merged total=\(all.count)")
            if shared.isEmpty {
                print("⚠️ \(contextPrefix) shared list is empty")
            }
            // 友達招待プレミアム体験：所有家計簿に新しい参加者が増えていないかチェック
            Task { [weak self] in await self?.checkOwnerReferralRewards() }
            return true
            
        } catch {
            self.lastError = error
            print("❌ \(contextPrefix) error:", error)
            // 取得失敗。既存（キャッシュ）一覧は消さずに保持し、エラー可視化＋自動リトライ。
            loadFailed = true
            scheduleAutoReloadRetry()
            return false
        }
    }

    func handleRemoteChange() async {
        let existing = ledgers
        let reloadSucceeded = await reloadLedgers(logContext: "remoteChange")
        let targets = reloadSucceeded ? ledgers : existing
        await refreshCachedRecords(for: targets)
    }

    // MARK: - 友達招待プレミアム体験（オーナー付与）

    /// 所有している共有家計簿に新しい参加者が増えていたら、オーナーにプレミアム体験を付与する。
    /// CloudKit の CKShare 参加者数を前回値（ベースライン）と比較して検知する。
    func checkOwnerReferralRewards() async {
        // 過剰な CKShare 取得を避けるため 30 秒に1回までに制限
        if let last = lastReferralCheck, Date().timeIntervalSince(last) < 30 { return }
        lastReferralCheck = Date()

        let owned = ownedLedgers
        guard !owned.isEmpty else { return }

        for ledger in owned {
            guard let count = try? await acceptedParticipantCount(for: ledger) else { continue }

            let initKey = "referral.participants.init.\(ledger.id.recordName)"
            let baseKey = "referral.participants.baseline.\(ledger.id.recordName)"

            // 初回観測時は既存参加者を遡及付与しないようベースラインだけ記録
            guard defaults.bool(forKey: initKey) else {
                defaults.set(count, forKey: baseKey)
                defaults.set(true, forKey: initKey)
                continue
            }

            let baseline = defaults.integer(forKey: baseKey)
            guard count != baseline else { continue }

            // ベースラインを更新（増減どちらも追従。減少時は再参加での再付与を防ぐ）
            defaults.set(count, forKey: baseKey)
            guard count > baseline else { continue }

            // 増えた参加者の人数ぶん付与（1人 = referralTrialDaysPerJoin 日）
            let newJoins = count - baseline
            var grantedTotal = 0
            for _ in 0..<newJoins {
                grantedTotal += (purchaseManager?.grantReferralTrial() ?? 0)
            }
            if grantedTotal > 0 {
                let days = purchaseManager?.referralTrialRemainingDays ?? grantedTotal
                globalToast = ToastState(
                    message: "友達が参加しました！プレミアムを\(grantedTotal)日間プレゼント🎉（残り\(days)日）",
                    systemImage: "gift.fill",
                    actionTitle: nil,
                    action: nil
                )
            }
        }
    }

    /// 指定した所有家計簿の CKShare で、オーナー以外の「承諾済み」参加者数を返す
    private func acceptedParticipantCount(for ledger: SharedLedger) async throws -> Int {
        let rootRecord = try await db.record(for: ledger.id)
        guard let shareRef = rootRecord.share else { return 0 }
        let shareRecord = try await db.record(for: shareRef.recordID)
        guard let share = shareRecord as? CKShare else { return 0 }
        return share.participants.filter {
            $0.role != .owner && $0.acceptanceStatus == .accepted
        }.count
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
            if let ckError = error as? CKError {
                presentQuotaExceededToast(
                    operation: "createLedger",
                    containerIdentifier: container.containerIdentifier ?? "default",
                    ledgerID: nil,
                    error: ckError
                )
            }
            return nil
        }
    }
    
    func updateLedger(_ ledger: SharedLedger, name: String, icon: String, colorHex: String) async {
        do {
            let targetDB = database(for: ledger)
            let record = try await targetDB.record(for: ledger.id)
            record["name"] = name as CKRecordValue
            record["icon"] = icon as CKRecordValue
            record["colorHex"] = colorHex as CKRecordValue
            let saved = try await targetDB.save(record)
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
            saveLedgerCache()
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

    @discardableResult
    func leaveLedger(_ ledger: SharedLedger) async -> Bool {
        guard !isOwned(ledger) else {
            print("leaveLedger: owned ledger, skip")
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
            let rootRecord = try await sharedDB.record(for: ledger.id)
            if let shareRef = rootRecord.share {
                try await sharedDB.deleteRecord(withID: shareRef.recordID)
            } else {
                try await sharedDB.deleteRecord(withID: ledger.id)
            }
            ledgerSourceMap[ledger.id] = nil
            transactionsByLedger[ledger.id] = nil
            categoriesByLedger[ledger.id] = nil
            deletingLedgerIDs.remove(ledger.id)
            saveLedgerCache()
            showToast(message: "「\(ledger.name)」から脱退しました")
            return true
        } catch {
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                ledgerSourceMap[ledger.id] = nil
                transactionsByLedger[ledger.id] = nil
                categoriesByLedger[ledger.id] = nil
                deletingLedgerIDs.remove(ledger.id)
                showToast(message: "「\(ledger.name)」から脱退しました")
                return true
            }

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
            ReviewRequestManager.shared.recordSuccessfulSave()
        } catch {
            self.lastError = error
            if let ckError = error as? CKError {
                presentQuotaExceededToast(
                    operation: "addTransaction",
                    containerIdentifier: container.containerIdentifier ?? "default",
                    ledgerID: ledger.id,
                    error: ckError
                )
            }
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
    @MainActor
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
        switch source(for: ledger) {
        case .shared: return sharedDB
        case .private: return db
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
        print("ℹ️ [SharedLedgerStore] prepareShare strategy=recordHierarchySharing rootRecord=\(ledger.id.recordName) zone=\(ledger.id.zoneID.zoneName) database=privateCloudDatabase")
        // ① 常にサーバー側の最新 rootRecord を取得
        let rootRecord = try await db.record(for: ledger.id)
        try await backfillRecordHierarchyIfNeeded(for: ledger)
        
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
                    if let ckError = error as? CKError {
                        presentQuotaExceededToast(
                            operation: "prepareShare.modifyRecords.retry",
                            containerIdentifier: container.containerIdentifier ?? "default",
                            shareID: share.recordID.recordName,
                            ledgerID: ledger.id,
                            error: ckError
                        )
                    }
                    throw error
                }
            } else {
                if let ckError = error as? CKError {
                    presentQuotaExceededToast(
                        operation: "prepareShare.modifyRecords",
                        containerIdentifier: container.containerIdentifier ?? "default",
                        shareID: share.recordID.recordName,
                        ledgerID: ledger.id,
                        error: ckError
                    )
                }
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

    /// 旧バージョンで作成されたレコードのうち parent が未設定のものを補正する
    /// - Note: record hierarchy sharing で共有対象になるよう、SharedCategory / SharedTransaction の parent を root ledger に揃える
    private func backfillRecordHierarchyIfNeeded(for ledger: SharedLedger) async throws {
        let ledgerReference = CKRecord.Reference(recordID: ledger.id, action: .none)
        let categoryPredicate = NSPredicate(format: "%K == %@", SharedCategory.FieldKey.ledgerRef, ledgerReference)
        let transactionPredicate = NSPredicate(format: "%K == %@", SharedTransaction.FieldKey.ledgerRef, ledgerReference)

        let categoryQuery = CKQuery(recordType: SharedCategory.recordType, predicate: categoryPredicate)
        let transactionQuery = CKQuery(recordType: SharedTransaction.recordType, predicate: transactionPredicate)

        let categoryRecords = try await queryRecords(categoryQuery, in: db, zoneID: ledger.id.zoneID)
        let transactionRecords = try await queryRecords(transactionQuery, in: db, zoneID: ledger.id.zoneID)

        let parentRef = CKRecord.Reference(recordID: ledger.id, action: .none)
        var recordsToFix: [CKRecord] = []

        for record in categoryRecords where record.parent?.recordID != ledger.id {
            record.parent = parentRef
            recordsToFix.append(record)
        }

        for record in transactionRecords where record.parent?.recordID != ledger.id {
            record.parent = parentRef
            recordsToFix.append(record)
        }

        guard recordsToFix.isEmpty == false else { return }

        for chunk in recordsToFix.chunked(into: 200) {
            _ = try await db.modifyRecords(
                saving: chunk,
                deleting: [],
                savePolicy: .changedKeys,
                atomically: false
            )
        }

        print("ℹ️ [SharedLedgerStore] backfillRecordHierarchyIfNeeded fixed=\(recordsToFix.count) ledger=\(ledger.id.recordName)")
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

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, isEmpty == false else { return isEmpty ? [] : [self] }

        var chunks: [[Element]] = []
        chunks.reserveCapacity((count + size - 1) / size)

        var start = startIndex
        while start < endIndex {
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            chunks.append(Array(self[start..<end]))
            start = end
        }
        return chunks
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
