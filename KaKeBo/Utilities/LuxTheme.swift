//
//  Utilities/LuxTheme.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct LuxCard: ViewModifier {
    @Environment(\.appVisualStyle) private var visualStyle
    @Environment(\.colorScheme) private var scheme
    var corner: CGFloat = 16
    func body(content: Content) -> some View {
        let isBusiness = visualStyle == .business
        let fillColor = scheme == .dark ? Color.white.opacity(isBusiness ? 0.03 : 0.06) : .white
        let strokeColor = scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)

        return content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: isBusiness ? 10 : corner, style: .continuous)
                    .fill(fillColor)
            )
            .overlay {
                if isBusiness {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(strokeColor, lineWidth: 1)
                }
            }
            .shadow(
                color: .black.opacity(isBusiness ? 0 : (scheme == .dark ? 0.35 : 0.06)),
                radius: isBusiness ? 0 : 10,
                y: isBusiness ? 0 : 5
            )
    }
}

struct HomeCard: ViewModifier {
    @Environment(\.appVisualStyle) private var visualStyle
    @Environment(\.appHomeCardStyle) private var homeCardStyle
    @Environment(\.colorScheme) private var scheme
    var corner: CGFloat = 16

    @ViewBuilder
    func body(content: Content) -> some View {
        if visualStyle == .business {
            content
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.03) : .white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10), lineWidth: 1)
                )
        } else {
            switch homeCardStyle {
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
}
extension View {
    func luxCard(corner: CGFloat = 16) -> some View {
        modifier(LuxCard(corner: corner))
    }
    func homeCard(corner: CGFloat = 16) -> some View {
        modifier(HomeCard(corner: corner))
    }
}
