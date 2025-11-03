//
//  Views/Components/MonthlyHeaderCard.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct MonthlyHeaderCard: View {
    let income: Int
    let expense: Int
    let balance: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今月の収支")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Spacer()
                    Text(currency(balance))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(balance >= 0 ? Color.green : Color.red)
                        .contentTransition(.numericText()) // iOS17+
                }
                
                HStack(spacing: 12) {
                    StatPill(title: "支出", value: expense, icon: "arrow.down.left.circle.fill", base: .red.opacity(0.75))
                    StatPill(title: "収入", value: income, icon: "arrow.up.right.circle.fill", base: .green.opacity(0.75))
                }
            }
            .luxCard()
        }
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "JPY"
        f.currencySymbol = "¥"
        f.maximumFractionDigits = 0
        return f.string(from: n as NSNumber) ?? "¥\(n)"
    }
}

private struct StatPill: View {
    let title: String
    let value: Int
    let icon: String
    let base: Color
    
    // ▼ iPhone SE など小型端末判定
    private var isSmallPhone: Bool {
#if os(iOS)
        UIScreen.main.bounds.height <= 667 // iPhone SE 第2世代相当
#else
        false
#endif
    }
    
    // ▼ アイコンのサイズスケール
    private var iconScale: CGFloat { isSmallPhone ? 0.75 : 1.0 }
    
    var body: some View {
        HStack(spacing: 10 * iconScale) {
            Image(systemName: icon)
                .foregroundStyle(.white)
                .frame(width: 24 * iconScale, height: 24 * iconScale)
                .background(
                    Circle()
                        .fill(base.gradient)
                        .frame(width: 28 * iconScale, height: 28 * iconScale)
                )
            
            VStack(alignment: .leading, spacing: 2 * iconScale) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currency(value))
                    .font(.headline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12 * iconScale)
        .background(
            RoundedRectangle(cornerRadius: 12 * iconScale, style: .continuous)
                .fill(base.opacity(0.12))
        )
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}
