//
//  Models/AppTheme.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI

extension AppTheme.Preset {
    var title: String {
        switch self {
        case .default: return "デフォルト"
        case .green:   return "緑系"
        case .red:     return "赤系"
        case .orange:  return "オレンジ系"
        case .custom:  return "カスタム"
        }
    }
    var accent: Color {
        switch self {
        case .default: return Color(.sRGB, red: 0.0,   green: 0.478, blue: 1.0,   opacity: 1)
        case .green:   return Color(.sRGB, red: 0.10,  green: 0.68,  blue: 0.26,  opacity: 1)
        case .red:     return Color(.sRGB, red: 0.92,  green: 0.23,  blue: 0.21,  opacity: 1)
        case .orange:  return Color(.sRGB, red: 1.00,  green: 0.49,  blue: 0.10,  opacity: 1)
        case .custom:  return .accentColor
        }
    }
}

extension AppTheme.HomeCardStyle {
    var title: String {
        switch self {
        case .luxe: return "立体感あり"
        case .flat: return "シンプル"
        }
    }
}

extension AppTheme.VisualStyle {
    var title: String {
        switch self {
        case .modern: return "標準"
        case .business: return "フラット"
        }
    }
}

struct RGBAColor: Codable, Equatable {
    var r: Double; var g: Double; var b: Double; var a: Double
    
    init(_ color: Color) {
        let ui = UIColor(color)
        // 現在のトレイトで確定色に解決
        let resolved = ui.resolvedColor(with: UITraitCollection.current)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        if resolved.getRed(&rr, green: &gg, blue: &bb, alpha: &aa) {
            r = Double(rr); g = Double(gg); b = Double(bb); a = Double(aa)
        } else {
            // フォールバック（systemBlue 相当）
            r = 0.0; g = 122.0/255.0; b = 1.0; a = 1.0
        }
    }
    
    var swiftUIColor: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
}

// MARK: - フォントファミリー（.fontDesign() で確実に動作する4種のみ）
enum AppFontFamily: String, Codable, CaseIterable, Identifiable {
    case systemDefault = "systemDefault"
    case rounded = "rounded"
    case serif = "serif"
    case monospaced = "monospaced"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .systemDefault: return "システム標準"
        case .rounded:       return "丸ゴシック"
        case .serif:         return "セリフ"
        case .monospaced:    return "等幅"
        }
    }

    /// .fontDesign() で適用するデザイン
    var fontDesign: Font.Design {
        switch self {
        case .systemDefault: return .default
        case .rounded:       return .rounded
        case .serif:         return .serif
        case .monospaced:    return .monospaced
        }
    }
}

struct AppTheme: Codable, Equatable {
    // アクセント
    enum Preset: String, Codable, CaseIterable { case `default`, green, red, orange, custom }
    enum HomeCardStyle: String, Codable, CaseIterable { case luxe, flat }
    enum VisualStyle: String, Codable, CaseIterable { case modern, business }
    
    // 現在有効なプリセット（カスタム編集をしたら custom に）
    var activePreset: Preset = .default

    // アクセント
    var useSameAccentForBoth: Bool = true
    var accentLightRGBA: RGBAColor = .init(Color.blue) // 例：デフォルト
    var accentDarkRGBA:  RGBAColor = .init(Color.blue)

    // 背景
    var useSameBackgroundForBoth: Bool = false
    var backgroundLightRGBA: RGBAColor = .init(Color(red: 250/255, green: 250/255, blue: 250/255))
    var backgroundDarkRGBA:  RGBAColor = .init(Color(red: 18/255, green: 18/255, blue: 18/255))

    // 入力まわり
    var prefersCustomKeypad: Bool = true
    var keypadIncomeRGBA: RGBAColor = .init(Color.green)
    var keypadExpenseRGBA: RGBAColor = .init(Color.red)
    // 表示上の収支カラー
    var incomeRGBA: RGBAColor = .init(Color.green)
    var expenseRGBA: RGBAColor = .init(Color.red)

    // ホームカード
    var homeCardStyle: HomeCardStyle = .luxe
    // アプリ全体のトーン
    var visualStyle: VisualStyle = .modern

    // フォントファミリー（nil = visualStyle に連動）
    var fontFamily: AppFontFamily?

    enum CodingKeys: String, CodingKey {
        case activePreset
        case useSameAccentForBoth
        case accentLightRGBA
        case accentDarkRGBA
        case useSameBackgroundForBoth
        case backgroundLightRGBA
        case backgroundDarkRGBA
        case prefersCustomKeypad
        case keypadIncomeRGBA
        case keypadExpenseRGBA
        case incomeRGBA
        case expenseRGBA
        case homeCardStyle
        case visualStyle
        case fontFamily
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activePreset = try c.decodeIfPresent(Preset.self, forKey: .activePreset) ?? .default
        useSameAccentForBoth = try c.decodeIfPresent(Bool.self, forKey: .useSameAccentForBoth) ?? true
        accentLightRGBA = try c.decodeIfPresent(RGBAColor.self, forKey: .accentLightRGBA) ?? .init(Color.blue)
        accentDarkRGBA = try c.decodeIfPresent(RGBAColor.self, forKey: .accentDarkRGBA) ?? .init(Color.blue)
        useSameBackgroundForBoth = try c.decodeIfPresent(Bool.self, forKey: .useSameBackgroundForBoth) ?? false
        backgroundLightRGBA = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundLightRGBA) ?? .init(Color(red: 250/255, green: 250/255, blue: 250/255))
        backgroundDarkRGBA = try c.decodeIfPresent(RGBAColor.self, forKey: .backgroundDarkRGBA) ?? .init(Color(red: 18/255, green: 18/255, blue: 18/255))
        prefersCustomKeypad = try c.decodeIfPresent(Bool.self, forKey: .prefersCustomKeypad) ?? true
        keypadIncomeRGBA = try c.decodeIfPresent(RGBAColor.self, forKey: .keypadIncomeRGBA) ?? .init(Color.green)
        keypadExpenseRGBA = try c.decodeIfPresent(RGBAColor.self, forKey: .keypadExpenseRGBA) ?? .init(Color.red)
        incomeRGBA = try c.decodeIfPresent(RGBAColor.self, forKey: .incomeRGBA) ?? .init(Color.green)
        expenseRGBA = try c.decodeIfPresent(RGBAColor.self, forKey: .expenseRGBA) ?? .init(Color.red)
        homeCardStyle = try c.decodeIfPresent(HomeCardStyle.self, forKey: .homeCardStyle) ?? .luxe
        visualStyle = try c.decodeIfPresent(VisualStyle.self, forKey: .visualStyle) ?? .modern
        fontFamily = try c.decodeIfPresent(AppFontFamily.self, forKey: .fontFamily)
    }
    
    mutating func apply(_ preset: Preset) {
        activePreset = preset
        switch preset {
        case .default:
            accentLightRGBA = .init(Color(.sRGB, red: 0.0, green: 0.478, blue: 1.0, opacity: 1))
            accentDarkRGBA  = accentLightRGBA
            useSameAccentForBoth = true
            backgroundLightRGBA = .init(Color(.sRGB, red: 250/255, green: 250/255, blue: 250/255, opacity: 1))
            backgroundDarkRGBA  = .init(Color(.sRGB, red: 18/255,  green: 18/255,  blue: 18/255,  opacity: 1))
            useSameBackgroundForBoth = false
            
        case .green:
            accentLightRGBA = .init(Color(.sRGB, red: 0.10, green: 0.68, blue: 0.26, opacity: 1))
            accentDarkRGBA  = accentLightRGBA
            useSameAccentForBoth = true
            backgroundLightRGBA = .init(Color(.sRGB, red: 250/255, green: 250/255, blue: 250/255, opacity: 1))
            backgroundDarkRGBA  = .init(Color(.sRGB, red: 18/255,  green: 18/255,  blue: 18/255,  opacity: 1))
            useSameBackgroundForBoth = false
            
        case .red:
            accentLightRGBA = .init(Color(.sRGB, red: 0.92, green: 0.23, blue: 0.21, opacity: 1))
            accentDarkRGBA  = accentLightRGBA
            useSameAccentForBoth = true
            backgroundLightRGBA = .init(Color(.sRGB, red: 250/255, green: 250/255, blue: 250/255, opacity: 1))
            backgroundDarkRGBA  = .init(Color(.sRGB, red: 18/255,  green: 18/255,  blue: 18/255,  opacity: 1))
            useSameBackgroundForBoth = false
            
        case .orange:
            accentLightRGBA = .init(Color(.sRGB, red: 1.00, green: 0.49, blue: 0.10, opacity: 1))
            accentDarkRGBA  = accentLightRGBA
            useSameAccentForBoth = true
            backgroundLightRGBA = .init(Color(.sRGB, red: 250/255, green: 250/255, blue: 250/255, opacity: 1))
            backgroundDarkRGBA  = .init(Color(.sRGB, red: 18/255,  green: 18/255,  blue: 18/255,  opacity: 1))
            useSameBackgroundForBoth = false
            
        case .custom:
            // 既存値を維持。以降は編集 UI で更新
            break
        }
    }
    
    mutating func markAsCustom() { activePreset = .custom }
    
    // —— ここが超重要：UI は必ずこのメソッド経由で色を取る ——
    func accentColor(for scheme: ColorScheme) -> Color {
        if activePreset != .custom {
            // プリセット運用時：light/dark で同じ色にしている前提
            return accentLightRGBA.swiftUIColor
        }
        if useSameAccentForBoth { return accentLightRGBA.swiftUIColor }
        return scheme == .dark ? accentDarkRGBA.swiftUIColor : accentLightRGBA.swiftUIColor
    }
    
    func backgroundColor(for scheme: ColorScheme) -> Color {
        if activePreset != .custom {
            // プリセット運用時：ライトは白系、ダークは暗め
            return scheme == .dark ? backgroundDarkRGBA.swiftUIColor : backgroundLightRGBA.swiftUIColor
        }
        if useSameBackgroundForBoth { return backgroundLightRGBA.swiftUIColor }
        return scheme == .dark ? backgroundDarkRGBA.swiftUIColor : backgroundLightRGBA.swiftUIColor
    }

    func keypadColor(isIncome: Bool) -> Color {
        isIncome ? keypadIncomeRGBA.swiftUIColor : keypadExpenseRGBA.swiftUIColor
    }

    func transactionColor(isIncome: Bool) -> Color {
        isIncome ? incomeRGBA.swiftUIColor : expenseRGBA.swiftUIColor
    }

    /// 解決済みフォントファミリー（nil の場合は visualStyle から自動決定）
    var resolvedFontFamily: AppFontFamily {
        if let fontFamily { return fontFamily }
        return visualStyle == .business ? .systemDefault : .rounded
    }
}
