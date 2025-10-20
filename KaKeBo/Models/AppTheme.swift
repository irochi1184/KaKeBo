//
//  AppTheme.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI

struct AppTheme: Codable, Equatable {
    var name: String = "Default"
    var accentRGBA: RGBAColor = .init(Color(UIColor.systemBlue))
    var allowSystemDarkMode: Bool = true
    var forceDarkMode: Bool = false
    
    // 追加したくなったら：背景色/カード色/テキスト色などを増やせます
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
