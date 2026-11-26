import SwiftUI

struct CategoryDetailTransaction: Identifiable {
    let id: String
    let categoryKey: String
    let date: Date
    let amount: Int
    let memo: String
}

struct CategoryBreakdownSheet: View {
    let title: String
    let type: TransactionType
    let transactions: [CategoryDetailTransaction]
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
                            isExpense: type == .expense
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .homeCard()

                    if breakdown.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "circle.dashed")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text(type == .expense ? "この月の支出がまだありません" : "この月の収入がまだありません")
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
                                                .frame(width: 44, height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("\(slice.name)をグラフに表示")
                                        .accessibilityValue(excludedKeys.contains(slice.filterKey) ? "オフ" : "オン")

                                        NavigationLink {
                                            transactionList(for: slice)
                                        } label: {
                                            HStack {
                                                Label(slice.name, systemImage: slice.symbolName ?? "tag.fill")
                                                    .labelStyle(.titleAndIcon)
                                                    .foregroundStyle(slice.color.opacity(excludedKeys.contains(slice.filterKey) ? 0.35 : 1.0))

                                                Spacer(minLength: 8)

                                                Text(currency(slice.value))
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(excludedKeys.contains(slice.filterKey) ? .secondary : .primary)
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            .frame(minHeight: 44)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
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

    private func transactionList(for slice: CategorySlice) -> some View {
        let rows = transactions.filter { $0.categoryKey == slice.filterKey }
            .sorted { $0.date > $1.date }

        return List {
            Section {
                ForEach(rows) { tx in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(tx.date, style: .date)
                            Spacer()
                            Text(currency(tx.amount))
                                .fontWeight(.semibold)
                        }
                        if !tx.memo.isEmpty {
                            Text(tx.memo)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(title)
            } footer: {
                Text("合計 \(currency(slice.value))（\(rows.count)件）")
            }
        }
        .navigationTitle(slice.name)
        .navigationBarTitleDisplayMode(.inline)
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
