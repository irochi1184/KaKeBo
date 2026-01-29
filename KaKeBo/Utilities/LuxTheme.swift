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
                .padding(.vertical, 12)
                .padding(.leading, 36)
                .padding(.trailing, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    NotebookPaperBackground(scheme: scheme)
                )
                .overlay(
                    NotebookMarginLine(scheme: scheme)
                )
        }
    }
}

private struct NotebookPaperBackground: View {
    let scheme: ColorScheme
    private var background: Color {
        scheme == .dark ? Color.white.opacity(0.04) : Color(red: 0.99, green: 0.98, blue: 0.96)
    }
    private var lineColor: Color {
        scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
    }

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let width = proxy.size.width
            let spacing: CGFloat = 18

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(background)

                Path { path in
                    var y: CGFloat = spacing
                    while y < height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: width, y: y))
                        y += spacing
                    }
                }
                .stroke(lineColor, lineWidth: 1)
            }
        }
    }
}

private struct NotebookMarginLine: View {
    let scheme: ColorScheme
    private var lineColor: Color {
        scheme == .dark ? Color.red.opacity(0.35) : Color.red.opacity(0.25)
    }

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                let x: CGFloat = 18
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: proxy.size.height))
            }
            .stroke(lineColor, style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
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
