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

@MainActor
final class PurchaseManager: ObservableObject {
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    
    static let premiumProductIDs: Set<String> = [
        "kakebo.premium.monthly",
        "kakebo.premium.yearly",
        "kakebo.premium.lifetime"
    ]
    
    private var updatesTask: Task<Void, Never>?   // ← 追加
    
    init() {
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
    
    var isPremiumActive: Bool { !purchasedProductIDs.isEmpty }
    
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
