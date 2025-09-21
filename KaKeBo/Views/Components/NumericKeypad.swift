//
//  Views/Components/NumericKeypad.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct NumericKeypad: View {
    @Binding var amount: Int
    var maxDigits: Int = 9
    var showLeadingZero: Bool = false
    
    init(amount: Binding<Int>, maxDigits: Int = 9, showLeadingZero: Bool = false) {
        self._amount = amount
        self.maxDigits = maxDigits
        self.showLeadingZero = showLeadingZero
    }
    
    private var digits: [String] = [
        "1","2","3",
        "4","5","6",
        "7","8","9",
        "00","0","⌫"
    ]
    
    var body: some View {
        VStack(spacing: 10) {
            // 金額表示（カンマ区切り）
            Text("¥ " + formatted(amount))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal)
            
            // クイック加算
            HStack(spacing: 8) {
                ForEach([1000, 3000, 5000, 10000], id: \.self) { add in
                    Button("+\(add)") { applyQuickAdd(add) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal)
            
            // テンキー
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(digits, id: \.self) { key in
                    Button { tap(key) } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.thinMaterial)
                            Text(key)
                                .font(.system(size: key == "⌫" ? 22 : 24, weight: .medium))
                        }
                        .frame(height: 54)
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.7).onEnded { _ in
                            if key == "⌫" { amount = 0 }
                        }
                    )
                    .accessibilityLabel(accessibilityLabel(for: key))
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(radius: 2, y: 1)
        .padding(.horizontal)
    }
    
    // MARK: - Private
    private func tap(_ key: String) {
        switch key {
        case "⌫": amount /= 10
        case "00": appendDigits("00")
        default: appendDigits(key)
        }
    }
    
    private func appendDigits(_ str: String) {
        if amount == 0, str == "00" { return }
        if amount == 0, let n = Int(str), n == 0, !showLeadingZero { return }
        
        let current = String(amount)
        let nextStr = current + str
        if nextStr.count > maxDigits { return }
        if let next = Int(nextStr) { amount = next }
    }
    
    private func applyQuickAdd(_ n: Int) {
        let max = Int(pow(10.0, Double(maxDigits))) - 1
        amount = min(amount + n, max)
    }
    
    private func formatted(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: n as NSNumber) ?? "\(n)"
    }
    
    private func accessibilityLabel(for key: String) -> String {
        switch key {
        case "⌫": return "1文字削除"
        case "00": return "ゼロ2つ"
        default: return "\(key)"
        }
    }
}
