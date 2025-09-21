import Foundation
import SwiftUI

struct Category: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var symbolName: String // SF Symbols 名
    var colorHex: String   // #RRGGBB

    init(id: UUID = UUID(), name: String, symbolName: String, color: Color = .blue) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.colorHex = color.toHexString()
    }

    var color: Color {
        Color.fromHex(colorHex) ?? .blue
    }
}