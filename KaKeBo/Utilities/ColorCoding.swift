//
//  ColorCoding.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/23.
//

import SwiftUI

func colorToHex(_ color: Color) -> String {
#if os(iOS)
    let ui = UIColor(color).resolvedColor(with: UITraitCollection.current)
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    ui.getRed(&r, green: &g, blue: &b, alpha: &a)
    let R = Int(round(r*255)), G = Int(round(g*255)), B = Int(round(b*255)), A = Int(round(a*255))
    return String(format: "#%02X%02X%02X%02X", R,G,B,A)
#else
    return "#000000FF"
#endif
}

func hexToColor(_ hex: String) -> Color? {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6 || s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
    let r = Double((v >> (s.count == 8 ? 24 : 16)) & 0xFF) / 255
    let g = Double((v >> (s.count == 8 ? 16 : 8))  & 0xFF) / 255
    let b = Double((v >> (s.count == 8 ? 8  : 0))  & 0xFF) / 255
    let a = s.count == 8 ? Double(v & 0xFF) / 255 : 1.0
    return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
}
