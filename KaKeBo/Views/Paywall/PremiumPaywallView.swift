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
    @Environment(\.openURL) private var openURL
    @StateObject private var pm = PurchaseManager()
    
    let accent: Color
    
    // 審査で必須の外部リンク
    private let termsURL = URL(string: "https://sneaky-truffle-e15.notion.site/297100819d8a80b989e3e873f3595ac6")!
    private let privacyURL = URL(string: "https://sneaky-truffle-e15.notion.site/297100819d8a80ad80e7ef9c6152d06b")!
    private let cancelHelpURL = URL(string: "https://support.apple.com/ja-jp/118428")!
    private let manageURL = URL(string: "https://apps.apple.com/account/subscriptions")!
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    
                    // MARK: - ヘッダー
                    VStack(spacing: 10) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(accent)
                        
                        Text("KaKeBo プレミアム")
                            .font(.title2.weight(.bold))
                        
                        Text("カテゴリ上限の解放、テーマの自由設定、通知の拡張、固定費テンプレート強化など、すべての機能を解放。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 8)
                    
                    // MARK: - 機能紹介 (FeatureCards)
                    featureCards
                    
                    // MARK: - プランセクション
                    planSection
                    
                    // MARK: - 復元 / 管理ボタン
                    restoreSection
                    
                    // MARK: - 法定リンク・補足
                    LegalBlock(
                        privacyURL: privacyURL,
                        termsURL: termsURL,
                        cancelHelpURL: cancelHelpURL
                    )
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .navigationTitle("プレミアムプラン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { CloseButton() }
            }
            .task { await pm.load() }
            .alert("エラー", isPresented: .constant(pm.errorMessage != nil), actions: {
                Button("OK") { pm.errorMessage = nil }
            }, message: { Text(pm.errorMessage ?? "") })
        }
        .tint(accent)
        .background(Color(uiColor: .systemBackground))
    }
    
    // MARK: - FeatureCards
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
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.10), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.10), radius: 18, y: 8)
    }
    
    // MARK: - プラン（サブスク or 買い切り）
    private var planSection: some View {
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
            
            // 🟡 買い切り補足をここに追加
            Text("こちらは一度購入いただくと永久的に全ての機能をご利用いただけます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - 復元 / 管理
    private var restoreSection: some View {
        VStack(spacing: 6) {
            Button {
                Task { await pm.restore() }
            } label: {
                Label("購入を復元する", systemImage: "arrow.clockwise.circle")
            }
            .font(.footnote.weight(.semibold))
            
            Button("サブスクリプションを管理") {
                openURL(manageURL)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
    
    // MARK: - 閉じるボタン
    private struct CloseButton: View {
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

// MARK: - FeatureCard コンポーネント（既存のまま）

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

// MARK: - Product Card

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
                Text("\(product.displayPrice)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(accent))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
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
        .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
    }
}

// MARK: - 法定リンクブロック

private struct LegalBlock: View {
    let privacyURL: URL
    let termsURL: URL
    let cancelHelpURL: URL
    
    var body: some View {
        VStack(spacing: 10) {
            Text("""
                 ・購入はApple IDに請求されます。
                 ・購入後は設定 > Apple ID > サブスクリプションで管理・解約できます。
                 """)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 6) {
                Link("プライバシーポリシー", destination: privacyURL)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Link("利用規約", destination: termsURL)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Link("購読の解約方法", destination: cancelHelpURL)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.footnote)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08))
        )
    }
}
