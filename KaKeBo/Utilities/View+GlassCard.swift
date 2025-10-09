//
//  Utilities/View+GlassCard.swift.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/08.
//

import SwiftUI

struct GlassCard: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    var corner: CGFloat = 18
    var blur: CGFloat = 10
    
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                ZStack {
                    // 透け＋ぼかし
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .blur(radius: blur)
                    
                    // 色味をほんのり
                    LinearGradient(
                        colors: scheme == .dark
                        ? [Color.white.opacity(0.04), Color.white.opacity(0.02)]
                        : [Color.white.opacity(0.35), Color.white.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .background(
                // 角の内側にハイライト（縁の艶出し）
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.clear)
            )
            .overlay(
                // うっすら白輪郭
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.08), radius: 12, y: 6)
    }
}

extension View {
    func glassCard(corner: CGFloat = 18, blur: CGFloat = 10) -> some View {
        self.modifier(GlassCard(corner: corner, blur: blur))
    }
}
