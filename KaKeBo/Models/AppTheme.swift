//
//  AppTheme.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI

struct AppTheme: Codable, Equatable {
    var name: String = "Default"
    
    // アクセント（ライト/ダーク個別 or 共通）
    var useSameAccentForBoth: Bool = true
    var accentLightRGBA: RGBAColor = .init(Color(UIColor.systemBlue))
    var accentDarkRGBA:  RGBAColor = .init(Color(UIColor.systemBlue))
    
    // Home 背景（ライト/ダーク個別 or 共通）
    var useSameBackgroundForBoth: Bool = true
    var backgroundLightRGBA: RGBAColor = .init(Color(red: 0.98, green: 0.98, blue: 0.98))
    var backgroundDarkRGBA:  RGBAColor = .init(Color(red: 0.06, green: 0.06, blue: 0.06))
    
    // 外観モード（アプリの実運用に使う）※プレビューは別途手動切替
    var allowSystemDarkMode: Bool = true
    var forceDarkMode: Bool = false
}

// 現在のカラースキームに応じて色を解決
extension AppTheme {
    func backgroundColor(for scheme: ColorScheme) -> Color {
        if useSameBackgroundForBoth {
            return backgroundLightRGBA.swiftUIColor
        } else {
            return (scheme == .dark ? backgroundDarkRGBA.swiftUIColor : backgroundLightRGBA.swiftUIColor)
        }
    }
    func accentColor(for scheme: ColorScheme) -> Color {
        if useSameAccentForBoth {
            return accentLightRGBA.swiftUIColor
        } else {
            return (scheme == .dark ? accentDarkRGBA.swiftUIColor : accentLightRGBA.swiftUIColor)
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
