//
//  Views/Components/NumericKeypad.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct NumericKeypad: View {
    enum Style { case attached, floating }
    
    @Binding var amount: Int
    var maxDigits: Int = 9
    var showLeadingZero: Bool = false
    var style: Style = .attached
    var isIncome: Bool = false       // ← ★ 追加：緑/赤の切替フラグ
    
    @Environment(\.colorScheme) private var scheme
    
    private let digits: [String] = [
        "1","2","3",
        "4","5","6",
        "7","8","9",
        "00","0","⌫"
    ]
    
    var body: some View {
        VStack(spacing: 12) {
            // 金額表示
            Text("¥ " + formatted(amount))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .foregroundStyle(labelColor) // ← ★ 金額表示も色味合わせ
            
            // クイック加算
            HStack(spacing: 8) {
                ForEach([1000, 3000, 5000, 10000], id: \.self) { add in
                    Button {
                        applyQuickAdd(add)
                        haptic(.light)
                    } label: {
                        Text("+\(decimal(add))")
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Capsule().fill(chipBackground))
                            .overlay(Capsule().stroke(chipBorder, lineWidth: 1))
                            .foregroundStyle(chipLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            
            // テンキー
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(digits, id: \.self) { key in
                    KeyButton(
                        title: key,
                        prominent: key == "⌫",
                        tint: keyButtonTint,         // ← ★ 色パラメータ渡す
                        action: {
                            tap(key)
                            haptic(.soft)
                        },
                        longPress: {
                            if key == "⌫" {
                                amount = 0
                                haptic(.rigid)
                            }
                        }
                    )
                    .frame(height: 54)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .padding(.vertical, 10)
        .background(containerBackground)
        .overlay(topHairline, alignment: .top)
        .clipShape(containerShape)
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        .padding(containerPadding)
    }
    
    // MARK: - カラー系定義
    
    private var baseColor: Color { isIncome ? .green : .red }
    
    private var labelColor: Color {
        baseColor.opacity(0.85)
    }
    
    private var chipBackground: Color {
        baseColor.opacity(scheme == .dark ? 0.25 : 0.15)
    }
    
    private var chipBorder: Color {
        baseColor.opacity(0.4)
    }
    
    private var chipLabel: Color {
        scheme == .dark ? .white : baseColor.opacity(0.9)
    }
    
    private var keyButtonTint: Color {
        baseColor.opacity(scheme == .dark ? 0.35 : 0.25)
    }
    
    @ViewBuilder
    private var containerBackground: some View {
        ZStack {
            // ぼかし用の ultraThinMaterial を重ねる
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.8)
                )
                .blur(radius: 10) // ← ★ ぼかし強度（お好みで5〜15）
            
            // カラーグラデーションで色味を薄くのせる
            LinearGradient(
                colors: scheme == .dark
                ? [baseColor.opacity(0.25), Color(white: 0.1)]
                : [baseColor.opacity(0.10), Color(white: 0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    @ViewBuilder
    private var topHairline: some View {
        switch style {
        case .attached:
            Divider().opacity(0.9)
        case .floating:
            EmptyView()
        }
    }
    
    private var containerShape: some Shape {
        switch style {
        case .attached: return AnyShape(Rectangle())
        case .floating: return AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    
    private var containerPadding: EdgeInsets {
        switch style {
        case .attached: return EdgeInsets() // 端まで広げる
        case .floating: return EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16)
        }
    }
    
    private var shadowColor: Color {
        switch style {
        case .attached: return .clear
        case .floating: return .black.opacity(scheme == .dark ? 0.35 : 0.06)
        }
    }
    
    private var shadowRadius: CGFloat { style == .attached ? 0 : 8 }
    private var shadowY: CGFloat { style == .attached ? 0 : 2 }
    
    // MARK: - 数値処理
    private func tap(_ key: String) {
        switch key {
        case "⌫": amount /= 10
        case "00": appendDigits("00")
        default:   appendDigits(key)
        }
    }
    
    private func appendDigits(_ str: String) {
        if amount == 0, str == "00" { return }
        if amount == 0, let n = Int(str), n == 0, !showLeadingZero { return }
        let current = (amount == 0) ? "" : String(amount)
        let nextStr = current + str
        if nextStr.count > maxDigits { return }
        if let next = Int(nextStr) { amount = next }
    }
    
    private func applyQuickAdd(_ n: Int) {
        let max = Int(pow(10.0, Double(maxDigits))) - 1
        amount = min(amount + n, max)
    }
    
    private func formatted(_ n: Int) -> String { decimal(n) }
    private func decimal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: n as NSNumber) ?? "\(n)"
    }
    
    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: style).impactOccurred()
#endif
    }
}

// MARK: - KeyButton with Tint

private struct KeyButton: View {
    let title: String
    var prominent: Bool = false
    var tint: Color = .gray.opacity(0.3)
    let action: () -> Void
    var longPress: (() -> Void)? = nil
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(tint.opacity(0.7), lineWidth: 1.2)
                    )
                Text(title)
                    .font(.system(size: title == "⌫" ? 22 : 24, weight: prominent ? .semibold : .medium))
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(PressedScaleStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.7).onEnded { _ in longPress?() }
        )
    }
}

private struct PressedScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
