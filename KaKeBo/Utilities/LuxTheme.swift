//
//  Utilities/LuxTheme.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct LuxCard: ViewModifier {
//    @EnvironmentObject var themeStore: ThemeStore
//    @Environment(\.colorScheme) private var scheme
    var corner: CGFloat = 16
    func body(content: Content) -> some View {
//        let accent = themeStore.theme.accentColor(for: scheme)
        content
            .padding(16)
            .background(
                .ultraThinMaterial.opacity(0.8),
                in: RoundedRectangle(cornerRadius: corner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}
extension View {
    func luxCard(corner: CGFloat = 16) -> some View {
        modifier(LuxCard(corner: corner))
    }
}
