import SwiftUI
import UIKit

extension Color {
    func toHexString(includeAlpha: Bool = false) -> String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255)), gi = Int(round(g * 255)), bi = Int(round(b * 255))
        if includeAlpha {
            let ai = Int(round(a * 255))
            return String(format: "#%02X%02X%02X%02X", ri, gi, bi, ai) // RRGGBBAA
        } else {
            return String(format: "#%02X%02X%02X", ri, gi, bi) // RRGGBB
        }
    }
    
    /// #RRGGBB または #RRGGBBAA（AA=不透明度）を受け付ける
    static func fromHex(_ hex: String) -> Color? {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if s.hasPrefix("#") { s.removeFirst() }
        
        // RRGGBB
        if s.count == 6, let v = UInt32(s, radix: 16) {
            let r = Double((v >> 16) & 0xFF) / 255.0
            let g = Double((v >> 8) & 0xFF) / 255.0
            let b = Double(v & 0xFF) / 255.0
            return Color(red: r, green: g, blue: b)
        }
        
        // RRGGBBAA（末尾AAがアルファ）
        if s.count == 8, let v = UInt32(s, radix: 16) {
            let r = Double((v >> 24) & 0xFF) / 255.0
            let g = Double((v >> 16) & 0xFF) / 255.0
            let b = Double((v >> 8) & 0xFF) / 255.0
            let a = Double(v & 0xFF) / 255.0
            return Color(.sRGB, red: r, green: g, blue: b, opacity: a)
        }
        return nil
    }
}
