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
                        
                        Text("カテゴリ・固定費・タグの上限解放に加え、収支カラーや通知設定までまとめてご利用いただけます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, 8)

                    // MARK: - 友達招待プレミアム体験中バナー
                    if pm.isReferralTrialActive {
                        HStack(spacing: 10) {
                            Image(systemName: "gift.fill")
                                .foregroundStyle(accent)
                            Text("プレミアム体験中（残り\(pm.referralTrialRemainingDays)日）")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(accent.opacity(0.12))
                        )
                    }

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
                subtitle: "アクセント色・背景色に加えて、収入/支出の表示カラーや電卓カラーも自由に変更できます。",
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
                subtitle: "無料プランは5件まで。6件目以降の固定費テンプレートを登録できるので、毎月の入力漏れを防げます。",
                accent: accent
            )
            FeatureCard(
                icon: "tag.fill",
                title: "タグを無制限に管理",
                subtitle: "支出やメモに自由にタグを付けて分類。無制限で追加・編集が可能に。目的別の分析や検索がよりスムーズに。",
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
            
            TrialBanner(text: planBannerText)
                .transition(.opacity.combined(with: .move(edge: .top)))
                .padding(.bottom, 2)
            
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
            
            Text(planFootnoteText)
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

    /// 無料トライアル（紹介オファー）付きのサブスクが存在するか
    private var hasFreeTrialOffer: Bool {
        pm.products.contains { $0.subscription?.introductoryOffer?.paymentMode == .freeTrial }
    }

    private var planBannerText: String {
        // 無料トライアルがある場合は最優先で訴求
        if hasFreeTrialOffer {
            return "年額プランは無料トライアル付き。気に入らなければ期間内の解約で料金はかかりません。"
        }
        let hasSubscription = pm.products.contains { $0.type == .autoRenewable }
        let hasLifetime = pm.products.contains { $0.type == .nonConsumable }
        switch (hasSubscription, hasLifetime) {
        case (true, true):
            return "月額・年額・買い切りから、使い方に合うプランを選べます"
        case (true, false):
            return "月額・年額プランから、使い方に合うプランを選べます"
        case (false, true):
            return "買い切りプランなら、一度の購入で継続してご利用いただけます"
        default:
            return "ご利用プランを選択して、プレミアム機能をご利用いただけます"
        }
    }

    private var planFootnoteText: String {
        let hasSubscription = pm.products.contains { $0.type == .autoRenewable }
        let hasLifetime = pm.products.contains { $0.type == .nonConsumable }
        switch (hasSubscription, hasLifetime) {
        case (true, true):
            return "サブスクリプションと買い切りの両方をご用意しています。購入前に表示価格と利用条件をご確認ください。"
        case (true, false):
            return "サブスクリプションプランです。更新タイミングや解約方法は「サブスクリプションを管理」から確認できます。"
        case (false, true):
            return "買い切りプランです。価格は購入画面に表示されます。"
        default:
            return "価格と利用条件は購入ボタンの表示内容をご確認ください。"
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

    // 無料トライアル（紹介オファー）の説明文。対象かつ適格な場合のみ表示
    @State private var trialText: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(product.displayName)
                    .font(.subheadline.weight(.bold))
                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if let trialText {
                    Text(trialText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                onPurchase()
            } label: {
                Text(trialText == nil ? product.displayPrice : "無料で開始")
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
        .task { await loadIntroOffer() }
    }

    /// 紹介オファー（無料トライアル）を確認し、適格なら説明文をセットする
    private func loadIntroOffer() async {
        guard
            let sub = product.subscription,
            let offer = sub.introductoryOffer,
            offer.paymentMode == .freeTrial
        else { return }
        // 過去にトライアル/オファーを利用済みのユーザーは対象外
        guard await sub.isEligibleForIntroOffer else { return }
        let period = Self.periodLengthText(offer.period)
        let unit = Self.periodUnitText(sub.subscriptionPeriod)
        trialText = "\(period)無料、その後 \(product.displayPrice)/\(unit)"
    }

    /// トライアル期間の長さ（例: 1週間 → 「7日間」）
    private static func periodLengthText(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:   return "\(period.value)日間"
        case .week:  return "\(period.value * 7)日間"
        case .month: return "\(period.value)か月間"
        case .year:  return "\(period.value)年間"
        @unknown default: return "\(period.value)"
        }
    }

    /// 課金周期の単位（例: 年額 → 「年」）
    private static func periodUnitText(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day:   return "日"
        case .week:  return "週"
        case .month: return "月"
        case .year:  return "年"
        @unknown default: return ""
        }
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

private struct TrialBanner: View {
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "gift.fill")
                .imageScale(.medium)
                .font(.body)
                .symbolRenderingMode(.hierarchical)
            Text(text)
                .font(.subheadline)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .accessibilityLabel("無料お試しのお知らせ")
    }
}
