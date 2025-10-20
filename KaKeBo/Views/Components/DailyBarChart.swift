//
//  Views/Components/DailyBarChart.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import Charts

struct DailyPoint: Identifiable {
    let date: Date
    let amount: Int
    var id: Date { date }
}

struct DailyBarChart: View {
    let series: [DailyPoint]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("日別推移（今月・支出）")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Chart(series) {
                BarMark(
                    x: .value("日", $0.date, unit: .day),
                    y: .value("金額", $0.amount)
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisTick()
                    AxisValueLabel(format: .dateTime.day().locale(Locale(identifier: "ja_JP")))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisTick()
                    AxisValueLabel {
                        if let n = v.as(Int.self) {
                            Text(currency(n))
                        }
                    }
                }
            }
            .frame(height: 220)
            .luxCard()
        }
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}
