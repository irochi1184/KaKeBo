//
//  Utilities/LuxTheme.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct LuxCard: ViewModifier {
//    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    var corner: CGFloat = 16
    func body(content: Content) -> some View {
//        let accent = themeStore.theme.accentColor(for: scheme)
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: corner)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : .white)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.06), radius: 10, y: 5)
            )
    }
}

struct HomeCard: ViewModifier {
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    var corner: CGFloat = 16

    func body(content: Content) -> some View {
        switch themeStore.theme.homeCardStyle {
        case .luxe:
            content.luxCard(corner: corner)
        case .flat:
            content
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.05) : .white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.06), lineWidth: 1)
                )
        }
    }
}
extension View {
    func luxCard(corner: CGFloat = 16) -> some View {
        modifier(LuxCard(corner: corner))
    }
    func homeCard(corner: CGFloat = 16) -> some View {
        modifier(HomeCard(corner: corner))
    }
}
