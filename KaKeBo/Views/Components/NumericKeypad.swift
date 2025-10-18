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
    var isIncome: Bool = false
    // サイズ調整用
    var sizeScale: CGFloat = 1.0               // 例: 0.8 で2割小さく
    var preferredHeightRatio: CGFloat? = nil    // 例: 0.33 で画面高の1/3
    var onHeightChange: ((CGFloat) -> Void)? = nil
    var onTapClose: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var scheme
    private let digits = ["1","2","3","4","5","6","7","8","9","00","0","⌫"]
    
    var body: some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { onHeightChange?(proxy.size.height) }
                        .onChange(of: proxy.size.height) { oldValue, newValue in
                            onHeightChange?(newValue)
                        }
                }
            )
    }
    
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 12 * sizeScale) {
            // 金額表示
            Text("¥ " + formatted(amount))
                .font(.system(size: 34 * sizeScale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16 * sizeScale)
                .foregroundStyle(labelColor)
            
            // クイック加算
            HStack(spacing: 8 * sizeScale) {
                ForEach([1000, 3000, 5000, 10000], id: \.self) { add in
                    Button {
                        applyQuickAdd(add); haptic(.light)
                    } label: {
                        Text("+\(decimal(add))")
                            .font(.system(size: 13 * sizeScale, weight: .semibold, design: .default))
                            .monospacedDigit()
                            .padding(.vertical, 6 * sizeScale)
                            .padding(.horizontal, 10 * sizeScale)
                            .background(Capsule().fill(chipBackground))
                            .overlay(Capsule().stroke(chipBorder, lineWidth: 1 * sizeScale))
                            .foregroundStyle(chipLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16 * sizeScale)
            
            // テンキー
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10 * sizeScale), count: 3),
                      spacing: 10 * sizeScale) {
                ForEach(digits, id: \.self) { key in
                    KeyButton(
                        title: key,
                        prominent: key == "⌫",
                        tint: keyButtonTint,
                        action: { tap(key); haptic(.soft) },
                        longPress: {
                            if key == "⌫" { amount = 0; haptic(.rigid) }
                        }
                    )
                    .frame(height: 54 * sizeScale) // ★ ボタン高さを縮小
                }
            }
                      .padding(.horizontal, 16 * sizeScale)
                      .padding(.bottom, 8 * sizeScale)
        }
        .padding(.vertical, 10 * sizeScale)
        .background(containerBackground)
        .overlay(topHairline, alignment: .top)
        .clipShape(containerShape)
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        .padding(containerPadding)
        
        // ★ 親から比率を指定されたら、その高さに合わせる
        .frame(height: preferredHeightRatio.map { UIScreen.main.bounds.height * $0 })
        .overlay(alignment: .topTrailing) {
            if let onTapClose {
                CloseKeyboardButton { onTapClose() }
                    .padding(.top, 8)
                    .padding(.trailing, 10)
            }
        }
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
    
    var sizeScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 12 * sizeScale)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12 * sizeScale)
                            .stroke(tint.opacity(0.7), lineWidth: 1.2 * sizeScale)
                    )
                Text(title)
                    .font(.system(size: (title == "⌫" ? 22 : 24) * sizeScale,
                                  weight: prominent ? .semibold : .medium))
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
