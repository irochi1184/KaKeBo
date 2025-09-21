//
//  Views/Components/CategoryCard.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//
//

import SwiftUI

struct CategoryCard: View {
    let name: String
    let symbolName: String
    let color: Color
    let isSelected: Bool
    
    var body: some View {
        // 複雑な計算は事前に変数へ
        let strokeColor: Color = isSelected ? .accentColor : .white.opacity(0.08)
        let lineWidth: CGFloat = isSelected ? 2 : 1
        let shadowOpacity: Double = isSelected ? 0.12 : 0.06
        let shadowRadius: CGFloat = isSelected ? 12 : 8
        let shadowY: CGFloat = isSelected ? 8 : 5
        
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(color.opacity(0.12))
                Image(systemName: symbolName)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(height: 54)
            
            Text(name)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(strokeColor, lineWidth: lineWidth)
        )
        .shadow(color: .black.opacity(shadowOpacity),
                radius: shadowRadius, y: shadowY)
    }
}
