//
//  Views/Components/CategoryCard.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//
//

import SwiftUI

struct CategoryCard: View {
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    let name: String
    let symbolName: String
    let color: Color
    let isSelected: Bool
    
    var body: some View {
        let strokeColor: Color = isSelected ? themeStore.theme.accentColor(for: scheme) : .white.opacity(0.08)
        let lineWidth: CGFloat = isSelected ? 2 : 1
        let shadowOpacity: Double = isSelected ? 0.10 : 0.04
        let shadowRadius: CGFloat = isSelected ? 8 : 4
        let shadowY: CGFloat = isSelected ? 5 : 3
        
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color.opacity(0.10))
                Image(systemName: symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(height: 44) // ← 小さめタイル
            
            Text(name)
                .font(.caption.weight(.medium)) // ← 小さめ文字
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10) // ← 余白も少しだけ
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(strokeColor, lineWidth: lineWidth)
        )
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
    }
}
