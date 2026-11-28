//
//  Views/Paywall/PremiumPaywallView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/20.
//  2026/07 デザイン刷新: 新機能ハイライト・無料/プレミアム比較表・プラン選択式UI
//

import SwiftUI
import StoreKit
import Combine

struct PremiumPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    @StateObject private var pm = PurchaseManager()

    let accent: Color

    // プラン選択・購入状態
    @State private var selectedProductID: String?
    @State private var isPurchasing = false
    // 無料トライアル（紹介オファー）の対象プラン: productID → 「◯日間無料」
    @State private var trialTexts: [String: String] = [:]

    // 審査で必須の外部リンク
    private let termsURL = URL(string: "https://sneaky-truffle-e15.notion.site/297100819d8a80b989e3e873f3595ac6")!
    private let privacyURL = URL(string: "https://sneaky-truffle-e15.notion.site/297100819d8a80ad80e7ef9c6152d06b")!
    private let cancelHelpURL = URL(string: "https://support.apple.com/ja-jp/118428")!
    private let manageURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    heroSection

                    if !pm.purchasedProductIDs.isEmpty {
                        statusBanner(icon: "checkmark.seal.fill", text: "プレミアムをご利用中です。いつもありがとうございます！")
                    } else if pm.isReferralTrialActive {
                        statusBanner(icon: "gift.fill", text: "友達招待のプレミアム体験中（残り\(pm.referralTrialRemainingDays)日）")
                    }

                    newFeatureSection
                    comparisonSection
                    planSection
                    restoreSection

                    LegalBlock(
                        privacyURL: privacyURL,
                        termsURL: termsURL,
                        cancelHelpURL: cancelHelpURL
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(alignment: .top) {
                // ヒーロー背景のグラデーション
                LinearGradient(
                    colors: [accent.opacity(scheme == .dark ? 0.28 : 0.16), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 280)
                .ignoresSafeArea()
            }
            .navigationTitle("プレミアムプラン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { CloseButton() }
            }
            .task {
                await pm.load()
                await loadIntroOffers()
                // 年額プランをデフォルト選択（なければ先頭）
                if selectedProductID == nil {
                    selectedProductID = pm.products.first { $0.id == "kakebo.premium.yearly" }?.id
                        ?? pm.products.first?.id
                }
            }
            .alert("エラー", isPresented: .constant(pm.errorMessage != nil), actions: {
                Button("OK") { pm.errorMessage = nil }
            }, message: { Text(pm.errorMessage ?? "") })
        }
        .tint(accent)
    }

    // MARK: - ヒーロー

    private var heroSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: [accent, accent.opacity(0.55)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 76, height: 76)
                    .shadow(color: accent.opacity(0.35), radius: 16, y: 8)
                Image(systemName: "crown.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
            }

            Text("KaKeBo プレミアム")
                .font(.system(.title2, design: .rounded).weight(.bold))

            Text("上限を気にせず、あなた仕様の家計簿に。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    private func statusBanner(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(accent)
            Text(text)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(accent.opacity(0.12))
        )
    }

    // MARK: - 新機能ハイライト

    private var newFeatureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("新登場")

            NewFeatureCard(
                icon: "lock.iphone",
                title: "ウィジェットでカテゴリ予算",
                subtitle: "「食費の残り ¥12,500」をホーム画面・ロック画面に常時表示。買い物中に、あといくら使えるかすぐわかる。",
                accent: accent
            )
            NewFeatureCard(
                icon: "photo.on.rectangle.angled",
                title: "レシート写真をそのまま保存",
                subtitle: "取引ごとに写真を5枚まで添付。「これ何の出費だっけ？」をなくします。",
                accent: accent
            )
        }
    }

    // MARK: - 無料 / プレミアム比較表

    private struct CompareRow: Identifiable {
        let id = UUID()
        let feature: String
        let free: String     // "—" は非対応
        let premium: String  // "○" はチェックマーク表示
        var isNew: Bool = false
    }

    private let compareRows: [CompareRow] = [
        CompareRow(feature: "ウィジェットのカテゴリ別表示", free: "—", premium: "○", isNew: true),
        CompareRow(feature: "取引への写真添付", free: "—", premium: "5枚/件", isNew: true),
        CompareRow(feature: "カテゴリ数", free: "12件", premium: "無制限"),
        CompareRow(feature: "固定費テンプレート", free: "5件", premium: "無制限"),
        CompareRow(feature: "タグでの分類・検索", free: "—", premium: "○"),
        CompareRow(feature: "フィルター結果のグラフ表示", free: "月3回", premium: "無制限"),
        CompareRow(feature: "CSVエクスポート", free: "月3回", premium: "無制限"),
        CompareRow(feature: "エクスポートのカスタム期間", free: "—", premium: "○"),
        CompareRow(feature: "収支カラー・電卓カラーのカスタム", free: "—", premium: "○"),
        CompareRow(feature: "通知の文面・条件カスタム", free: "—", premium: "○")
    ]

    private var comparisonSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("プレミアムでできること")

            VStack(spacing: 0) {
                // 表ヘッダー
                HStack {
                    Text("機能")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("無料")
                        .frame(width: 56)
                    Text("プレミアム")
                        .frame(width: 76)
                        .foregroundStyle(accent)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                ForEach(Array(compareRows.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        HStack(spacing: 6) {
                            Text(row.feature)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                            if row.isNew {
                                Text("NEW")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(accent))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(row.free)
                            .font(.footnote)
                            .foregroundStyle(row.free == "—" ? .tertiary : .secondary)
                            .frame(width: 56)

                        Group {
                            if row.premium == "○" {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(accent)
                            } else {
                                Text(row.premium)
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(accent)
                            }
                        }
                        .frame(width: 76)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(index.isMultiple(of: 2) ? Color.primary.opacity(0.03) : .clear)
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
            )
        }
    }

    // MARK: - プラン選択

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("プランを選ぶ")

            if pm.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
            } else if pm.products.isEmpty {
                Text("プランを取得できませんでした。少し時間をおいてお試しください。")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 10) {
                    ForEach(pm.products, id: \.id) { p in
                        PlanCard(
                            product: p,
                            accent: accent,
                            isSelected: selectedProductID == p.id,
                            isOwned: pm.purchasedProductIDs.contains(p.id),
                            badge: badgeText(for: p),
                            trialText: trialTexts[p.id],
                            perMonthText: perMonthText(for: p)
                        ) {
                            withAnimation(.snappy(duration: 0.2)) { selectedProductID = p.id }
                        }
                    }
                }

                purchaseButton
                    .padding(.top, 4)

                Text(ctaFootnote)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var selectedProduct: Product? {
        pm.products.first { $0.id == selectedProductID }
    }

    private var selectedIsOwned: Bool {
        guard let id = selectedProductID else { return false }
        return pm.purchasedProductIDs.contains(id)
    }

    private var purchaseButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            isPurchasing = true
            Task {
                let ok = await pm.purchase(product)
                isPurchasing = false
                if ok { dismiss() }
            }
        } label: {
            Group {
                if isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text(ctaTitle)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                Capsule().fill(
                    LinearGradient(colors: [accent, accent.opacity(0.75)],
                                   startPoint: .leading, endPoint: .trailing)
                )
            )
            .foregroundStyle(.white)
            .shadow(color: accent.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(selectedProduct == nil || selectedIsOwned || isPurchasing)
        .opacity(selectedIsOwned ? 0.5 : 1)
    }

    private var ctaTitle: String {
        guard let product = selectedProduct else { return "プランを選択してください" }
        if selectedIsOwned { return "ご利用中のプランです" }
        if trialTexts[product.id] != nil { return "無料トライアルを開始" }
        if product.type == .nonConsumable { return "買い切りで購入する" }
        return "プレミアムに登録する"
    }

    private var ctaFootnote: String {
        guard let product = selectedProduct else {
            return "価格と利用条件は購入ボタンの表示内容をご確認ください。"
        }
        if let trial = trialTexts[product.id], let sub = product.subscription {
            return "\(trial)でお試し。終了後は \(product.displayPrice)/\(Self.periodUnitText(sub.subscriptionPeriod)) で自動更新されます。期間中の解約で料金はかかりません。"
        }
        if product.type == .nonConsumable {
            return "一度のお支払いで、プレミアム機能を継続してご利用いただけます。"
        }
        if let sub = product.subscription {
            return "\(product.displayPrice)/\(Self.periodUnitText(sub.subscriptionPeriod)) で自動更新されます。いつでも解約できます。"
        }
        return "価格と利用条件は購入ボタンの表示内容をご確認ください。"
    }

    /// 年額プランに「おすすめ・◯%お得」バッジを付ける
    private func badgeText(for product: Product) -> String? {
        guard product.id == "kakebo.premium.yearly" else { return nil }
        if let pct = yearlySavingsPercent {
            return "おすすめ・\(pct)%お得"
        }
        return "おすすめ"
    }

    /// 月額×12 と年額の比較による割引率
    private var yearlySavingsPercent: Int? {
        guard let monthly = pm.products.first(where: { $0.id == "kakebo.premium.monthly" }),
              let yearly = pm.products.first(where: { $0.id == "kakebo.premium.yearly" }) else { return nil }
        let full = monthly.price * Decimal(12)
        guard full > 0, yearly.price < full else { return nil }
        let pct = ((full - yearly.price) / full * Decimal(100)) as NSDecimalNumber
        let value = Int(truncating: pct)
        return value > 0 ? value : nil
    }

    /// 年額プランの「月あたり◯円」表示
    private func perMonthText(for product: Product) -> String? {
        guard product.id == "kakebo.premium.yearly" else { return nil }
        let perMonth = product.price / Decimal(12)
        return "月あたり \(perMonth.formatted(product.priceFormatStyle))"
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
    }

    // MARK: - 共通パーツ

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }

    private struct CloseButton: View {
        @Environment(\.dismiss) private var dismiss
        var body: some View {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: - 無料トライアル（紹介オファー）

    /// 各サブスクの紹介オファー（無料トライアル）適格性を確認する
    private func loadIntroOffers() async {
        var texts: [String: String] = [:]
        for p in pm.products {
            guard let sub = p.subscription,
                  let offer = sub.introductoryOffer,
                  offer.paymentMode == .freeTrial else { continue }
            // 過去にトライアル/オファーを利用済みのユーザーは対象外
            guard await sub.isEligibleForIntroOffer else { continue }
            texts[p.id] = "\(Self.periodLengthText(offer.period))無料"
        }
        trialTexts = texts
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

// MARK: - 新機能ハイライトカード

private struct NewFeatureCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.08)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 42, height: 42)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                    Text("NEW")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(accent))
                        .foregroundStyle(.white)
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    LinearGradient(colors: [accent.opacity(0.45), accent.opacity(0.1)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - プラン選択カード

private struct PlanCard: View {
    let product: Product
    let accent: Color
    let isSelected: Bool
    let isOwned: Bool
    let badge: String?
    let trialText: String?
    let perMonthText: String?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.4))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(product.displayName)
                            .font(.subheadline.weight(.bold))
                        if isOwned {
                            Text("ご利用中")
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(accent.opacity(0.15)))
                                .foregroundStyle(accent)
                        }
                    }
                    if let trialText {
                        Text("\(trialText)で試せる")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(accent)
                    } else if let perMonthText {
                        Text(perMonthText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if product.type == .nonConsumable {
                        Text("一度のお支払いでずっと使える")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    Text(unitText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? accent : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 1.6 : 0.8)
            )
            .overlay(alignment: .topTrailing) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accent))
                        .foregroundStyle(.white)
                        .offset(x: -10, y: -9)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var unitText: String {
        if product.type == .nonConsumable { return "買い切り" }
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        switch period.unit {
        case .day:   return "/日"
        case .week:  return "/週"
        case .month: return "/月"
        case .year:  return "/年"
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
