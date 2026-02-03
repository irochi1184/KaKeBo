import SwiftUI

struct CategoryBreakdownSheet: View {
    let title: String
    let breakdown: [CategorySlice]
    let currentTotal: Int
    let previousTotal: Int

    @State private var excludedKeys: Set<String> = []

    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject private var themeStore: ThemeStore

    private var filteredBreakdown: [CategorySlice] {
        breakdown.filter { !excludedKeys.contains($0.filterKey) }
    }

    private var displayedTotal: Int {
        filteredBreakdown.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(title)
                            .font(.headline)
                            .padding(.horizontal, 4)

                        CategoryDonutChart(
                            breakdown: filteredBreakdown,
                            currentTotal: currentTotal,
                            previousTotal: previousTotal,
                            minShareToShowLabel: 0.08,
                            isExpense: true
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .homeCard()

                    if breakdown.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "circle.dashed")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("今月の支出がまだありません")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .homeCard()
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("カテゴリ別内訳")
                                .font(.headline)

                            VStack(spacing: 8) {
                                ForEach(breakdown) { slice in
                                    HStack(spacing: 10) {
                                        Button {
                                            toggle(slice)
                                        } label: {
                                            Image(systemName: excludedKeys.contains(slice.filterKey) ? "square" : "checkmark.square.fill")
                                                .imageScale(.medium)
                                                .foregroundStyle(excludedKeys.contains(slice.filterKey) ? .secondary : slice.color)
                                                .frame(width: 24)
                                        }
                                        .buttonStyle(.plain)

                                        Label(slice.name, systemImage: slice.symbolName ?? "tag.fill")
                                            .labelStyle(.titleAndIcon)
                                            .foregroundStyle(slice.color.opacity(excludedKeys.contains(slice.filterKey) ? 0.35 : 1.0))

                                        Spacer(minLength: 8)

                                        Text(currency(slice.value))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(excludedKeys.contains(slice.filterKey) ? .secondary : .primary)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                    .onTapGesture { toggle(slice) }
                                    Divider().opacity(0.2)
                                }
                            }

                            HStack(spacing: 12) {
                                Button("全て含める") { excludedKeys.removeAll() }
                                Button("全て除外") { excludedKeys = Set(breakdown.map { $0.filterKey }) }
                                    .tint(.secondary)
                                Spacer()
                                Text("表示合計: \(currency(displayedTotal))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        }
                        .homeCard()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
            .background(
                themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea()
            )
            .navigationTitle("円グラフの詳細")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: breakdown) { _, _ in
            excludedKeys.removeAll()
        }
    }

    private func toggle(_ slice: CategorySlice) {
        if excludedKeys.contains(slice.filterKey) {
            excludedKeys.remove(slice.filterKey)
        } else {
            excludedKeys.insert(slice.filterKey)
        }
    }

    private func currency(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return "¥" + (formatter.string(from: n as NSNumber) ?? "\(n)")
    }
}
