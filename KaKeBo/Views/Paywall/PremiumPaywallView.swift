//
//  Views/Paywall/PremiumPaywallView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/20.
//

import SwiftUI
import StoreKit
import Combine

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var pm = PurchaseManager()
    
    let accent: Color
    var features: [String] = [
        "広告なしの快適体験",
        "毎月ToDoの自動登録と通知拡張",
        "テーマ拡張（色・背景の高度カスタム）",
        "大量データでも快適なパフォーマンス"
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    
                    featureList
                    
                    productList
                    
                    restoreSection
                }
                .padding()
            }
            .navigationTitle("プレミアムプラン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await pm.load() }
            .alert("エラー", isPresented: .constant(pm.errorMessage != nil), actions: {
                Button("OK") { pm.errorMessage = nil }
            }, message: {
                Text(pm.errorMessage ?? "")
            })
        }
        .tint(accent)
    }
    
    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .imageScale(.large)
                .font(.system(size: 36))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(accent))
            
            Text("10秒で家計簿、さらに快適に")
                .font(.title3.weight(.semibold))
            Text("プレミアムで、記録・集計・通知・テーマすべてがレベルアップ。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
    
    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(features, id: \.self) { f in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(accent)
                    Text(f).font(.subheadline)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    
    private var productList: some View {
        VStack(spacing: 12) {
            if pm.isLoading {
                ProgressView().padding(.vertical, 24)
            } else if pm.products.isEmpty {
                Text("プランを取得できませんでした。少し時間をおいてお試しください。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(pm.products, id: \.id) { p in
                    ProductRow(product: p, accent: accent) {
                        Task {
                            let ok = await pm.purchase(p)
                            if ok { dismiss() }
                        }
                    }
                }
            }
        }
    }
    
    private var restoreSection: some View {
        VStack(spacing: 6) {
            Button("購入を復元する") {
                Task { await pm.restore() }
            }
            .font(.footnote.weight(.semibold))
            
            Button("サブスクリプションを管理") {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct ProductRow: View {
    let product: Product
    let accent: Color
    let onPurchase: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .font(.subheadline.weight(.semibold))
                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button(product.displayPrice) { onPurchase() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
