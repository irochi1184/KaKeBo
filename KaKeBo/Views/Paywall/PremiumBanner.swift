//
//  Views/Paywall/PremiumBanner.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/20.
//

import SwiftUI

struct PremiumBanner: View {
    let accent: Color
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.15))
                        .frame(width: 42, height: 42)
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.white)
                        .imageScale(.large)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("プレミアムプラン")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("広告なし・カテゴリ数無制限・自由自在なテーマ拡張")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // 右矢印
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                LinearGradient(colors: [accent, accent.opacity(0.65)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("プレミアムプランの詳細を開く")
    }
}
