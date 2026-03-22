import SwiftUI

struct FlatCardBackground: View {
    @Environment(\.appVisualStyle) private var visualStyle
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 14

    var body: some View {
        let isFlat = visualStyle == .business
        let fill = scheme == .dark ? Color.white.opacity(isFlat ? 0.03 : 0.06) : Color.white
        let stroke = scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)

        RoundedRectangle(cornerRadius: isFlat ? 10 : cornerRadius, style: .continuous)
            .fill(fill)
            .overlay {
                if isFlat {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                }
            }
    }
}

struct FlatCardModifier: ViewModifier {
    @Environment(\.appVisualStyle) private var visualStyle
    @Environment(\.colorScheme) private var scheme
    var cornerRadius: CGFloat = 14
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        let isFlat = visualStyle == .business
        return content
            .padding(padding)
            .background(FlatCardBackground(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(isFlat ? 0 : (scheme == .dark ? 0.35 : 0.06)),
                    radius: isFlat ? 0 : 10,
                    y: isFlat ? 0 : 5)
    }
}

struct FlatListRowBackground: View {
    @Environment(\.appVisualStyle) private var visualStyle
    @Environment(\.colorScheme) private var scheme

    var appliesFlatBorder: Bool = true

    var body: some View {
        let isFlat = visualStyle == .business && appliesFlatBorder
        let fill = scheme == .dark ? Color.white.opacity(0.06) : Color.white
        let stroke = scheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)

        RoundedRectangle(cornerRadius: isFlat ? 10 : 12, style: .continuous)
            .fill(fill)
            .overlay {
                if isFlat {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                }
            }
            .padding(.vertical, 2)
    }
}

extension View {
    func flatCard(cornerRadius: CGFloat = 14, padding: CGFloat = 12) -> some View {
        modifier(FlatCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}
