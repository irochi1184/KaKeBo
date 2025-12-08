//
//  Views/Components/NumericKeypad.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct NumericKeypad: View {
    enum Style { case attached, floating }
    enum CalcOp { case add, sub, mul, div }
    
    @Binding var amount: Int
    var maxDigits: Int = 9
    var showLeadingZero: Bool = false
    var style: Style = .attached
    var isIncome: Bool = false
    var baseColorOverride: Color? = nil
    // サイズ調整用
    var sizeScale: CGFloat = 1.0
    var preferredHeightRatio: CGFloat? = nil
    var onHeightChange: ((CGFloat) -> Void)? = nil
    var onTapClose: (() -> Void)? = nil
    
    @Environment(\.colorScheme) private var scheme
    private let digits = ["1","2","3","4","5","6","7","8","9","00","0","⌫"]
    
    // ▼ 簡易電卓状態
    @State private var accumulator: Int = 0
    @State private var pendingOp: CalcOp? = nil
    @State private var lastInputWasOp = false
    
    // ▼ 小型画面対応（iPhone SE2 など）
    private var isSmallPhone: Bool {
#if os(iOS)
        UIScreen.main.bounds.height <= 667
#else
        false
#endif
    }
    private var scale: CGFloat {
        sizeScale * (isSmallPhone ? 0.88 : 1.0)
    }
    private var keyHeight: CGFloat {
        (isSmallPhone ? 48 : 54) * scale
    }
    private var opColumnWidth: CGFloat {
        (isSmallPhone ? 66 : 70) * scale
    }
    private var gridMinWidth: CGFloat {
        (isSmallPhone ? 92 : 96) * scale
    }
    
    var body: some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { onHeightChange?(proxy.size.height) }
                        .onChange(of: proxy.size.height) { _, newValue in
                            onHeightChange?(newValue)
                        }
                }
            )
    }
    
    // MARK: - 式または金額表示
    private var displayText: String {
        if let op = pendingOp {
            let lhs = decimal(accumulator)
            let sym = opSymbol(op)
            let rhs = lastInputWasOp ? "" : decimal(amount)
            return rhs.isEmpty ? "\(lhs) \(sym)" : "\(lhs) \(sym) \(rhs)"
        } else {
            return "¥ " + formatted(amount)
        }
    }
    private func opSymbol(_ op: CalcOp) -> String {
        switch op {
        case .add: return "＋"
        case .sub: return "－"
        case .mul: return "×"
        case .div: return "÷"
        }
    }
    
    // MARK: - レイアウト
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 12 * scale) {
            // 上部：数値 or 式
            Text(displayText)
                .font(.system(size: 34 * scale, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 10 * scale)
                .foregroundStyle(labelColor)
            
            // クイック加算
            HStack(spacing: 8 * scale) {
                ForEach([1000, 3000, 5000, 10000], id: \.self) { add in
                    Button {
                        applyQuickAdd(add); haptic(.light); lastInputWasOp = false
                    } label: {
                        Text("+\(decimal(add))")
                            .font(.system(size: 13 * scale, weight: .semibold))
                            .monospacedDigit()
                            .padding(.vertical, 6 * scale)
                            .padding(.horizontal, 10 * scale)
                            .background(Capsule().fill(chipBackground))
                            .overlay(Capsule().stroke(chipBorder, lineWidth: 1 * scale))
                            .foregroundStyle(chipLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16 * scale)
            
            // 本体：数字 + 演算子列
            HStack(spacing: 8 * scale) {
                // 数字パッド
                let gridColumns = Array(
                    repeating: GridItem(.flexible(minimum: gridMinWidth), spacing: 8 * scale),
                    count: 3
                )
                
                LazyVGrid(columns: gridColumns, spacing: 8 * scale) {
                    ForEach(digits, id: \.self) { key in
                        KeyButton(
                            title: key,
                            prominent: key == "⌫",
                            tint: keyButtonTint,
                            action: { tap(key); haptic(.soft) },
                            longPress: {
                                if key == "⌫" { amount = 0; haptic(.rigid); lastInputWasOp = false }
                            },
                            sizeScale: scale
                        )
                        .frame(height: keyHeight)
                    }
                }
                
                // 演算子列
                VStack(spacing: 8 * scale) {
                    OperatorButton("＋") { operatorTapped(.add) }
                    OperatorButton("－") { operatorTapped(.sub) }
                    OperatorButton("×", onTap: { operatorTapped(.mul) }, onLongPress: { operatorTapped(.div) })
                    OperatorButton("＝") { equalsTapped() }
                }
                .frame(width: opColumnWidth)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6 * scale)
            // ❌ 負の下パディングは白抜けの原因になるので廃止
            .padding(.bottom, 8 * scale)
        }
        .padding(.vertical, 10 * scale)
        .background(containerBackground) // ← 不透明ベースに変更
        .overlay(topHairline, alignment: .top)
        .clipShape(containerShape)
        .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
        .padding(containerPadding)
        .frame(height: preferredHeightRatio.map {
            let base = UIScreen.main.bounds.height * $0
            // 小画面はほんの少しだけ圧縮（大きさを維持しつつ安全側）
            return isSmallPhone ? base * 0.92 : base
        })
        .overlay(alignment: .topTrailing) {
            if let onTapClose {
                CloseKeyboardButton { onTapClose() }
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }
        }
    }
    
    // MARK: - オペレーターボタン
    @ViewBuilder
    private func OperatorButton(_ symbol: String, onTap: @escaping () -> Void, onLongPress: (() -> Void)? = nil) -> some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 12 * scale)
                    .fill(.ultraThinMaterial) // 内部はOK（下地が不透明になったため白発光しない）
                    .overlay(
                        RoundedRectangle(cornerRadius: 12 * scale)
                            .stroke(baseColor.opacity(0.55), lineWidth: 1.2 * scale)
                    )
                Text(symbol)
                    .font(.system(size: 22 * scale, weight: .semibold))
                    .foregroundStyle(baseColor)
            }
        }
        .buttonStyle(PressedScaleStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.7).onEnded { _ in onLongPress?() }
        )
        .frame(height: keyHeight)
    }
    
    // MARK: - 電卓ロジック
    private func operatorTapped(_ op: CalcOp) {
        if lastInputWasOp {
            pendingOp = op
            return
        }
        if let p = pendingOp {
            accumulator = evaluate(lhs: accumulator, rhs: amount, op: p)
            amount = 0
        } else {
            accumulator = amount
            amount = 0
        }
        pendingOp = op
        lastInputWasOp = true
    }
    
    private func equalsTapped() {
        guard let p = pendingOp else { return }
        let result = evaluate(lhs: accumulator, rhs: amount, op: p)
        amount = clampToDigits(result)
        accumulator = 0
        pendingOp = nil
        lastInputWasOp = false
        haptic(.light)
    }
    
    private func evaluate(lhs: Int, rhs: Int, op: CalcOp) -> Int {
        let r: Int
        switch op {
        case .add: r = lhs + rhs
        case .sub: r = lhs - rhs
        case .mul: r = lhs * rhs
        case .div: r = rhs == 0 ? lhs : lhs / rhs
        }
        return clampToDigits(r)
    }
    
    private func clampToDigits(_ n: Int) -> Int {
        let limit = Int(pow(10.0, Double(maxDigits))) - 1
        return Swift.max(Swift.min(n, limit), -limit)
    }
    
    // MARK: - 見た目系
    private var baseColor: Color { baseColorOverride ?? (isIncome ? .green : .red) }
    private var labelColor: Color { baseColor.opacity(0.85) }
    private var chipBackground: Color { baseColor.opacity(scheme == .dark ? 0.25 : 0.15) }
    private var chipBorder: Color { baseColor.opacity(0.4) }
    private var chipLabel: Color { scheme == .dark ? .white : baseColor.opacity(0.9) }
    private var keyButtonTint: Color { baseColor.opacity(scheme == .dark ? 0.35 : 0.25) }
    
    // ★ 不透明ベースに変更（白四角の原因だった “素材＋ブラー” を撤去）
    @ViewBuilder
    private var containerBackground: some View {
        let base: Color = {
            if scheme == .dark { return Color(red: 0.08, green: 0.08, blue: 0.09) } // ほぼ黒（不透明）
            else { return Color(white: 0.98) } // 明るめ（不透明）
        }()
        ZStack {
            // 不透明ベース
            RoundedRectangle(cornerRadius: style == .attached ? 0 : 16, style: .continuous)
                .fill(base)
            // 軽いグラデの味付け（透明度を低くして“明るくなりすぎ”を防ぐ）
            RoundedRectangle(cornerRadius: style == .attached ? 0 : 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: scheme == .dark
                        ? [baseColor.opacity(0.14), .clear]
                        : [baseColor.opacity(0.06), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .allowsHitTesting(false)
            // 枠線
            RoundedRectangle(cornerRadius: style == .attached ? 0 : 16, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.08 : 0.15), lineWidth: 0.8)
        }
    }
    
    @ViewBuilder private var topHairline: some View {
        switch style { case .attached: Divider().opacity(0.9); case .floating: EmptyView() }
    }
    private var containerShape: some Shape {
        switch style {
        case .attached: AnyShape(Rectangle())
        case .floating: AnyShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
    private var containerPadding: EdgeInsets {
        switch style {
        case .attached: .init()
        case .floating: .init(top: 0, leading: 16, bottom: 8, trailing: 16)
        }
    }
    private var shadowColor: Color { style == .attached ? .clear : .black.opacity(scheme == .dark ? 0.35 : 0.06) }
    private var shadowRadius: CGFloat { style == .attached ? 0 : 8 }
    private var shadowY: CGFloat { style == .attached ? 0 : 2 }
    
    // MARK: - 入力ロジック
    private func tap(_ key: String) {
        switch key {
        case "⌫": amount /= 10
        case "00": appendDigits("00")
        default: appendDigits(key)
        }
        lastInputWasOp = false
    }
    
    private func appendDigits(_ str: String) {
        if lastInputWasOp { amount = 0 }
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
        let f = NumberFormatter(); f.numberStyle = .decimal
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
                RoundedRectangle(cornerRadius: 8 * sizeScale)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8 * sizeScale)
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
