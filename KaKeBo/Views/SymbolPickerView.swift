import SwiftUI

struct SymbolPickerView: View {
    @Binding var selected: String
    @State private var query: String = ""

    private let symbols: [String] = [
        // 使いそうな SF Symbols の一例（必要に応じて増減）
        "cart", "cart.fill",
        "tram", "tram.fill",
        "bus", "bus.fill",
        "bicycle", "figure.walk",
        "fork.knife", "takeoutbag.and.cup.and.straw.fill",
        "gamecontroller", "gamecontroller.fill",
        "house", "house.fill",
        "heart", "heart.fill",
        "banknote", "yensign.circle.fill",
        "creditcard.fill", "gift.fill",
        "wifi", "bolt.fill",
        "book.fill", "graduationcap.fill",
        "hammer.fill", "wrench.and.screwdriver.fill",
        "gearshape.fill", "tag.fill",
        "leaf.fill", "camera.fill"
    ]

    var filtered: [String] {
        guard !query.isEmpty else { return symbols }
        return symbols.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("検索", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                    ForEach(filtered, id: \.self) { name in
                        Button {
                            selected = name
                        } label: {
                            VStack(spacing: 8) {
                                Image(systemName: name)
                                    .font(.system(size: 24))
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                selected == name ? Color.accentColor : Color.secondary.opacity(0.25),
                                                lineWidth: 1
                                            )
                                    )

                                Text(name.replacingOccurrences(of: ".fill", with: ""))
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }
}
