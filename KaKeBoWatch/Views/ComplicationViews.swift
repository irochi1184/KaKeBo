//
//  ComplicationViews.swift
//  KaKeBoWatch
//
//  コンプリケーション用ビュー
//  （WidgetKit for watchOS で使用）
//

import SwiftUI
import WidgetKit

// MARK: - Circular コンプリケーション（今日の支出）

struct CircularComplicationView: View {
    let todayExpense: Int
    let budget: Int

    var progress: Double {
        guard budget > 0 else { return 0 }
        return min(Double(todayExpense) / Double(budget), 1.0)
    }

    var body: some View {
        Gauge(value: progress) {
            Image(systemName: "yensign")
        } currentValueLabel: {
            Text(compactAmount(todayExpense))
                .font(.system(.caption2, design: .rounded))
        }
        .gaugeStyle(.accessoryCircular)
    }
}

// MARK: - Rectangular コンプリケーション（月次サマリー）

struct RectangularComplicationView: View {
    let monthExpense: Int
    let monthIncome: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("KaKeBo")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(.secondary)
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption2)
                Text("¥\(monthExpense)")
                    .font(.caption2)
            }
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption2)
                Text("¥\(monthIncome)")
                    .font(.caption2)
            }
        }
    }
}

// MARK: - Inline コンプリケーション

struct InlineComplicationView: View {
    let monthBalance: Int

    var body: some View {
        Text("収支 ¥\(monthBalance)")
    }
}

// MARK: - ヘルパー

private func compactAmount(_ amount: Int) -> String {
    if amount >= 10000 {
        let man = Double(amount) / 10000.0
        return String(format: "%.1f万", man)
    }
    return "¥\(amount)"
}
