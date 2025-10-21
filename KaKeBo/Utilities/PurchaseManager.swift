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
    
    // ★ あなたの Product ID に合わせて
    static let premiumProductIDs: Set<String> = [
        "kakebo.premium.monthly",
        "kakebo.premium.yearly",
        "kakebo.premium.lifetime"
    ]
    
    func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            // 商品取得
            products = try await Product.products(for: Array(Self.premiumProductIDs))
                .sorted(by: { $0.price < $1.price })
            
            // 購入状態の復元 — StoreKit.Transaction をフル修飾して衝突回避
            var owned: Set<String> = []
            for id in Self.premiumProductIDs {
                if let vr = await StoreKit.Transaction.latest(for: id) {
                    switch vr {
                    case .verified(let skTx):
                        if isActive(skTx) { owned.insert(id) }
                    case .unverified:
                        break
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
                if case .verified(let skTx) = verification {
                    if isActive(skTx) {
                        purchasedProductIDs.insert(skTx.productID)
                    }
                    await skTx.finish()
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
    
    // MARK: - Helpers
    /// サブスクは期限切れ／取消を考慮。買い切りは取消がなければ有効。
    private func isActive(_ t: StoreKit.Transaction) -> Bool {
        if let revocation = t.revocationDate { return revocation > Date() ? true : false }
        if let exp = t.expirationDate { return exp > Date() }      // サブスク系
        return true                                                // 非消費型など
    }
}
