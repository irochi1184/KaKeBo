//
//  Views/Components/CategoryDonutChart.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import Charts

struct CategorySlice: Identifiable {
    let id: UUID
    let name: String
    let color: Color
    let value: Int
}

struct CategoryDonutChart: View {
    let breakdown: [CategorySlice]
    let currentTotal: Int
    let previousTotal: Int
    var minShareToShowLabel: Double = 0.08
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // 見出し + 先月比バッジ
            HStack {
                Text("カテゴリ別（今月）")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                DiffBadge(current: currentTotal, previous: previousTotal, mode: .expense) // ← ここ！
            }
            
            Chart(breakdown) { (item: CategorySlice) in
                SectorMark(
                    angle: .value("支出", item.value),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(item.color)
                .annotation(position: .overlay) {
                    if share(of: item) >= minShareToShowLabel {
                        VStack(spacing: 2) {
                            Text(item.name)
                            Text(currency(item.value))
                        }
                        .font(.caption2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(2)
                    }
                }
            }
            .frame(height: 220)
            
            // レジェンド（上位のみ）
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                ForEach(breakdown.prefix(6)) { item in
                    HStack(spacing: 8) {
                        Circle().fill(item.color).frame(width: 10, height: 10)
                        Text(item.name).font(.caption)
                        Spacer()
                        Text(currency(item.value))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
    
    // MARK: - Helpers
    private var total: Int { breakdown.reduce(0) { $0 + $1.value } }
    private func share(of item: CategorySlice) -> Double {
        guard total > 0 else { return 0 }
        return Double(item.value) / Double(total)
    }
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}

// 先月比の小さなバッジ
private struct DiffBadge: View {
    enum Mode { case expense, balance }  // ← 追加
    let current: Int
    let previous: Int
    var mode: Mode = .expense            // ← 既定は “支出”
    
    var body: some View {
        let percent: Double? = {
            switch mode {
            case .expense:
                let prev = max(0, previous)
                let curr = max(0, current)
                guard prev > 0 else { return nil }
                return (Double(curr - prev) / Double(prev)) * 100.0
            case .balance:
                let denom = abs(Double(previous))
                guard denom > 0 else { return nil }
                return (Double(current - previous) / denom) * 100.0
            }
        }()
        
        // 表示テキスト & 色
        let (text, bg, icon): (String, Color, String) = {
            if let p = percent {
                let v = round(p) // 小数不要なら丸め
                if v > 0 {
                    // 支出: 赤（悪化） / 収支: 緑（改善）
                    let color: Color = (mode == .expense) ? .red : .green
                    return ("支出先月比 +\(Int(v))%", color, "arrow.up.right")
                } else if v < 0 {
                    let color: Color = (mode == .expense) ? .green : .red
                    return ("支出先月比 \(Int(v))%", color, "arrow.down.right")
                } else {
                    return ("支出先月比 ±0%", .secondary, "arrow.right")
                }
            } else {
                // 前月0円などで %が出せない時
                return ("支出先月比 —", .secondary, "minus")
            }
        }()
        
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(bg.gradient.opacity(0.85)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.1), lineWidth: 1))
    }
}

