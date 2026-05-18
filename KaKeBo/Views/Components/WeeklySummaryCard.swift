//
//  WeeklySummaryCard.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2026/05/18.
//

import SwiftUI

/// ホーム画面に表示する週間サマリーカード
struct WeeklySummaryCard: View {
    let summary: WeeklySummaryService.Summary
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.appExpenseColor) private var expenseColor
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { themeStore.theme.accentColor(for: scheme) }

    private let dayLabels = ["月", "火", "水", "木", "金", "土", "日"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // タイトル行
            HStack {
                Image(systemName: "calendar.day.timeline.leading")
                    .foregroundStyle(accent)
                Text("今週のまとめ")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // 今週の支出 + 先週比
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今週の支出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(currency(summary.thisWeekTotal))
                        .font(.title2.weight(.bold).monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("先週の同時点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Text(currency(summary.lastWeekSamePointTotal))
                            .font(.callout.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let pct = summary.comparisonPercent {
                            comparisonBadge(pct)
                        }
                    }
                }
            }

            // 曜日別バーチャート
            weeklyBarChart

            // ひとことコメント
            HStack(spacing: 6) {
                Image(systemName: commentIcon)
                    .font(.caption)
                    .foregroundStyle(commentColor)
                Text(summary.comment)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    // MARK: - 曜日別バーチャート

    private var weeklyBarChart: some View {
        let maxAmount = max(summary.dailyExpenses.max() ?? 1, 1)

        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                VStack(spacing: 4) {
                    // 金額ラベル（千円単位）
                    if i <= summary.todayIndex && summary.dailyExpenses[i] > 0 {
                        Text(shortAmount(summary.dailyExpenses[i]))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.secondary)
                    } else {
                        Text(" ")
                            .font(.system(size: 9))
                    }

                    // バー
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor(for: i))
                        .frame(height: barHeight(amount: summary.dailyExpenses[i], max: maxAmount, index: i))

                    // 曜日ラベル
                    Text(dayLabels[i])
                        .font(.caption2)
                        .foregroundStyle(i == summary.todayIndex ? .primary : .secondary)
                        .fontWeight(i == summary.todayIndex ? .bold : .regular)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 100)
    }

    // MARK: - ヘルパー

    private func barColor(for index: Int) -> Color {
        if index > summary.todayIndex {
            return Color.secondary.opacity(0.15)
        }
        if index == summary.todayIndex {
            return expenseColor
        }
        return expenseColor.opacity(0.5)
    }

    private func barHeight(amount: Int, max: Int, index: Int) -> CGFloat {
        let minHeight: CGFloat = 6
        let maxHeight: CGFloat = 60

        if index > summary.todayIndex {
            return minHeight
        }
        if amount == 0 {
            return minHeight
        }
        return minHeight + CGFloat(amount) / CGFloat(max) * (maxHeight - minHeight)
    }

    @ViewBuilder
    private func comparisonBadge(_ percent: Double) -> some View {
        let isDown = percent < 0
        let symbol = isDown ? "▼" : "▲"
        let color: Color = isDown ? .green : .orange

        Text("\(symbol)\(Int(abs(percent)))%")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var commentIcon: String {
        guard let pct = summary.comparisonPercent else { return "lightbulb" }
        if pct <= -5 { return "hand.thumbsup" }
        if pct <= 5 { return "equal.circle" }
        return "exclamationmark.triangle"
    }

    private var commentColor: Color {
        guard let pct = summary.comparisonPercent else { return .secondary }
        if pct <= -5 { return .green }
        if pct <= 5 { return .blue }
        return .orange
    }

    private func currency(_ amount: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "¥\(amount)"
    }

    /// 千円単位の短縮表示（例: 1200 → "1.2k"）
    private func shortAmount(_ amount: Int) -> String {
        if amount >= 10000 {
            return String(format: "%.0f万", Double(amount) / 10000)
        }
        if amount >= 1000 {
            return String(format: "%.1fk", Double(amount) / 1000)
        }
        return "¥\(amount)"
    }
}
