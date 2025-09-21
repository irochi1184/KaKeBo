//
//  Views/Components/CategoryDonutChart.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import Charts

// これが無いと「Cannot find type 'CategorySlice'」になります
struct CategorySlice: Identifiable {
    let id: UUID
    let name: String
    let color: Color
    let value: Int
}

struct CategoryDonutChart: View {
    let breakdown: [CategorySlice]
    /// スライス内にラベルを出す最小比率（例: 8%）
    var minShareToShowLabel: Double = 0.08
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ別（今月）")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Chart(breakdown) { (item: CategorySlice) in  // ← 型を明示
                SectorMark(
                    angle: .value("支出", item.value),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .foregroundStyle(item.color)
                
                // スライス内ラベル（カテゴリ名 + 改行 + 金額）
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
