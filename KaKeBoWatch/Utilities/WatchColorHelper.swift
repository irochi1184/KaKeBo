//
//  WatchColorHelper.swift
//  KaKeBoWatch
//
//  Watch側で使用するカラー変換ヘルパー
//

import SwiftUI

extension Color {
    /// HEX文字列からColorを生成
    static func fromHex(_ hex: String) -> Color {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)

        let r, g, b: Double
        switch h.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 1
        }
        return Color(red: r, green: g, blue: b)
    }
}
