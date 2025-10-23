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
    
    var body: some View {
        NavigationStack {
            ZStack {
                premiumBackground
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        hero
                        
                        featureCards
                        
                        productSection
                        
                        restoreSection
                        
                        subtleDisclaimer
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("プレミアムプラン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { CloseButton() } }
            .task { await pm.load() }
            .alert("エラー", isPresented: .constant(pm.errorMessage != nil), actions: {
                Button("OK") { pm.errorMessage = nil }
            }, message: {
                Text(pm.errorMessage ?? "")
            })
        }
        .tint(accent)
    }
    
    // MARK: - Background
    
    private var premiumBackground: some View {
        let top = accent
        let bottom = Color.black.opacity(0.5)
        return ZStack {
            LinearGradient(colors: [top.opacity(0.20), bottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            // ほのかな光のオーブ
            Circle()
                .fill(accent.opacity(0.22))
                .blur(radius: 80)
                .frame(width: 220, height: 220)
                .offset(x: -120, y: -240)
            
            Circle()
                .fill(accent.opacity(0.18))
                .blur(radius: 100)
                .frame(width: 260, height: 260)
                .offset(x: 140, y: 380)
        }
    }
    
    // MARK: - Hero
    
    private var hero: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 88, height: 88)
                    .overlay(
                        Circle()
                            .stroke(accent.opacity(0.35), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                
                Image(systemName: "crown.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(accent)
            }
            
            Text("あなたの家計簿を、上質に。")
                .font(.title2.weight(.bold))
                .kerning(0.5)
            
            Text("カテゴリ上限の解放、自由なテーマ、賢い通知、固定費の拡張。すべてをプレミアムで。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
    
    // MARK: - Feature Cards (4つ)
    
    private var featureCards: some View {
        VStack(spacing: 12) {
            FeatureCard(
                icon: "square.grid.2x2.fill",
                title: "カテゴリ上限を解放",
                subtitle: "無料プランは12件まで。プレミアム加入でカテゴリ数は無制限。用途ごとに細かく分けても上限を気にしません。",
                accent: accent
            )
            FeatureCard(
                icon: "paintpalette.fill",
                title: "テーマを自由にカスタム",
                subtitle: "アクセント色・背景色、ライト/ダーク時での見え方まで細かく調整可能。ブランドカラーやお好みの配色で自分だけの家計簿に。",
                accent: accent
            )
            FeatureCard(
                icon: "bell.badge.fill",
                title: "通知を思い通りに",
                subtitle: "通知タイトル/本文のカスタムと、未登録日だけ・ToDoがある日だけ等の条件設定に対応。必要な時だけ、的確に通知。",
                accent: accent
            )
            FeatureCard(
                icon: "calendar.badge.clock",
                title: "固定費をさらに強化",
                subtitle: "無料プランは5件まで。6件目以降の固定費テンプレートの登録・運用が可能に。自動計上で漏れゼロへ。",
                accent: accent
            )
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
    }
    
    // MARK: - Products
    
    private var productSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("プラン")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            
            if pm.isLoading {
                ProgressView().padding(.vertical, 24)
            } else if pm.products.isEmpty {
                Text("プランを取得できませんでした。少し時間をおいてお試しください。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 10) {
                    ForEach(pm.products, id: \.id) { p in
                        ProductPremiumCard(product: p, accent: accent) {
                            Task {
                                let ok = await pm.purchase(p)
                                if ok { dismiss() }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Restore
    
    private var restoreSection: some View {
        VStack(spacing: 6) {
            Button {
                Task { await pm.restore() }
            } label: {
                Label("購入を復元する", systemImage: "arrow.clockwise.circle")
            }
            .font(.footnote.weight(.semibold))
            
            Button("サブスクリプションを管理") {
                if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
    
    private var subtleDisclaimer: some View {
        Text("いつでも解約可能。価格は地域・通貨により異なる場合があります。")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 6)
    }
    
    // MARK: - Components
    
    private struct CloseButton: View {
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

private struct FeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.14))
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(accent.opacity(0.25), lineWidth: 0.6)
                    )
                Image(systemName: icon)
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

private struct ProductPremiumCard: View {
    let product: Product
    let accent: Color
    let onPurchase: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.subheadline.weight(.bold))
                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                onPurchase()
            } label: {
                Text("今すぐアップグレード  \(product.displayPrice)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(accent)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.white.opacity(0.10), lineWidth: 0.8)
                )
        )
        .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
    }
}
