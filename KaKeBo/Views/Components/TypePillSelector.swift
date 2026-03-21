//
//  Views/Components/TypePillSelector.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct TypePillSelector: View {
    @Binding var type: TransactionType
    @Environment(\.appIncomeColor) private var incomeColor
    @Environment(\.appExpenseColor) private var expenseColor
    
    var body: some View {
        HStack(spacing: 10) {
            pill(title: "支出", isOn: type == .expense, base: expenseColor.opacity(0.8))
                .onTapGesture { withAnimation(.snappy) { type = .expense } }
            pill(title: "収入", isOn: type == .income, base: incomeColor.opacity(0.8))
                .onTapGesture { withAnimation(.snappy) { type = .income } }
        }
        .accessibilityElement(children: .contain)
    }
    
    private func pill(title: String, isOn: Bool, base: Color) -> some View {
        // 事前に見た目パラメータを決める（型推論を軽く）
        let fg: Color = isOn ? .white : base
        let stroke: Color = isOn ? .clear : .white.opacity(0.10)
        let shadowColor: Color = isOn ? base.opacity(0.25) : .clear
        
        // 選択時のグラデ背景
        let selectedBG = LinearGradient(
            gradient: Gradient(colors: [base, base.opacity(0.75)]),
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        let unselectedBG = base.opacity(0.12)
        
        return Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(fg)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        // ここを ViewBuilder で分岐（Color と LinearGradient をそのまま返す）
            .background(
                Group {
                    if isOn { selectedBG } else { unselectedBG }
                }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 10, y: 6)
            .contentShape(Rectangle())
            .animation(.snappy, value: isOn)
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

}
