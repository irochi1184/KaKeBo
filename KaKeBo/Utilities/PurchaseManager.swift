//
//  Utilities/PurchaseManager.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/20.
//

import Combine
import SwiftUI
import Foundation
import StoreKit
import WidgetKit

@MainActor
final class PurchaseManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = [] {
        didSet {
            // ウィジェット（プロセス外）からプレミアム状態を参照できるよう AppGroup にキャッシュする。
            // 招待体験分は premium.referralTrial.until を widget 側で直接参照するため、ここでは課金分のみ。
            UserDefaults.appGroup.set(!purchasedProductIDs.isEmpty, forKey: Self.purchasedCacheKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// ウィジェットが読むプレミアム（課金）状態のキャッシュキー
    nonisolated static let purchasedCacheKey = "premium.purchasedCache"
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    static let premiumProductIDs: Set<String> = [
        "kakebo.premium.monthly",
        "kakebo.premium.yearly",
        "kakebo.premium.lifetime"
    ]
    
    private var updatesTask: Task<Void, Never>?   // ← 追加
    
    init() {
        // 友達招待プレミアム体験の保存値を復元
        loadReferralTrial()
        // 起動時にトランザクション更新を常時監視
        startListeningForTransactions()
    }
    
    deinit {
        updatesTask?.cancel()
    }
    
    func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            // 商品取得
            products = try await Product.products(for: Array(Self.premiumProductIDs))
                .sorted(by: { $0.price < $1.price })
            
            // 所有状況の復元（最新トランザクション or 現行権利）
            var owned: Set<String> = []
            // iOS17+ なら currentEntitlements を優先、なければ latest(for:)
            if #available(iOS 17.0, *) {
                for await ent in StoreKit.Transaction.currentEntitlements {
                    if case .verified(let tx) = ent, Self.premiumProductIDs.contains(tx.productID), isActive(tx) {
                        owned.insert(tx.productID)
                    }
                }
            } else {
                for id in Self.premiumProductIDs {
                    if let vr = await StoreKit.Transaction.latest(for: id) {
                        if case .verified(let tx) = vr, isActive(tx) {
                            owned.insert(id)
                        }
                    }
                }
            }
            purchasedProductIDs = owned
        } catch {
            errorMessage = "商品情報の取得に失敗しました。"
        }
    }
    
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    applyPurchase(tx)            // ← ここでセット反映
                    await tx.finish()
                    return true
                }
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = "購入処理でエラーが発生しました。"
            return false
        }
    }
    
    func restore() async {
        do { try await AppStore.sync() } catch {
            errorMessage = "復元に失敗しました。"
        }
        await load()
    }
    
    // 課金（買い切り/サブスク）または友達招待プレミアム体験が有効ならプレミアム扱い
    var isPremiumActive: Bool { !purchasedProductIDs.isEmpty || isReferralTrialActive }
    // 下の2行はテスト用
//    var isPremiumActive = true   // プレミアムプラン加入
//    var isPremiumActive = false  // プレミアムプラン未加入

    // MARK: - 友達招待プレミアム体験（ローカル付与）

    /// 友達招待で付与されたプレミアム体験の有効期限（なければ nil）
    @Published private(set) var referralTrialUntil: Date?

    private enum TrialKeys {
        static let until = "premium.referralTrial.until"                  // Double（timeIntervalSinceReferenceDate）
        static let totalGrantedDays = "premium.referralTrial.totalGrantedDays" // Int（不正対策の累計上限管理）
    }

    /// 招待特典で付与できる累計日数の上限（自己招待などの乱用対策）
    nonisolated static let maxReferralTrialDays = 28
    /// 1回の参加成立で付与する日数
    nonisolated static let referralTrialDaysPerJoin = 7

    /// 友達招待プレミアム体験が現在有効か
    var isReferralTrialActive: Bool {
        guard let until = referralTrialUntil else { return false }
        return until > Date()
    }

    /// プレミアム体験の残り日数（切り上げ・有効でなければ0）
    var referralTrialRemainingDays: Int {
        guard let until = referralTrialUntil, until > Date() else { return 0 }
        return max(1, Int(ceil(until.timeIntervalSinceNow / 86_400)))
    }

    private func loadReferralTrial() {
        let raw = UserDefaults.appGroup.double(forKey: TrialKeys.until)
        if raw > 0 {
            referralTrialUntil = Date(timeIntervalSinceReferenceDate: raw)
        }
    }

    /// 友達が共有家計簿に参加したとき、オーナーへプレミアム体験を付与する。
    /// 既に体験中なら期限を延長する。累計上限に達している場合は付与しない。
    /// - Returns: 実際に付与した日数（0 なら未付与）
    @discardableResult
    func grantReferralTrial(days: Int = PurchaseManager.referralTrialDaysPerJoin) -> Int {
        let defaults = UserDefaults.appGroup
        let total = defaults.integer(forKey: TrialKeys.totalGrantedDays)
        guard total < Self.maxReferralTrialDays else { return 0 }

        let grantDays = min(days, Self.maxReferralTrialDays - total)
        let now = Date()
        // 体験中なら現在の期限から、切れていれば今から延長
        let base = max(referralTrialUntil ?? now, now)
        let newUntil = Calendar.current.date(byAdding: .day, value: grantDays, to: base) ?? base

        referralTrialUntil = newUntil
        defaults.set(newUntil.timeIntervalSinceReferenceDate, forKey: TrialKeys.until)
        defaults.set(total + grantDays, forKey: TrialKeys.totalGrantedDays)
        // 体験付与でプレミアム判定が変わるためウィジェットを更新
        WidgetCenter.shared.reloadAllTimelines()
        return grantDays
    }
    
    // MARK: - Updates listener
    private func startListeningForTransactions() {
        // すでに走っていれば再作成しない
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            // アプリ存続中ずっと待ち受け
            for await update in StoreKit.Transaction.updates {
                guard let self else { continue }
                if case .verified(let tx) = update {
                    // UI更新は MainActor 上（このクラスは @MainActor）
                    self.applyPurchase(tx)
                    await tx.finish()
                }
            }
        }
    }
    
    // 購入適用（買い切り／サブスク共通）
    private func applyPurchase(_ tx: StoreKit.Transaction) {
        if isActive(tx) {
            purchasedProductIDs.insert(tx.productID)
        } else {
            purchasedProductIDs.remove(tx.productID)
        }
    }
    
    // MARK: - Helpers
    /// サブスクは有効期限、買い切りは取消（返金）を考慮
    private func isActive(_ t: StoreKit.Transaction) -> Bool {
        // 取消済み（返金等）は無効
        if t.revocationDate != nil { return false }
        // サブスク等：期限が未来なら有効
        if let exp = t.expirationDate { return exp > Date() }
        // 非消費型（買い切り）は取消がなければ有効
        return true
    }
}
