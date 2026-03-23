import SwiftUI
import Charts

struct DailyTrendTransaction: Identifiable {
    let id: String
    let date: Date
    let categoryName: String
    let amount: Int
    let memo: String
}

struct DailyTrendDetailContext: Identifiable {
    let id = UUID()
    let title: String
    let series: [DailyCategoryPoint]
    let transactions: [DailyTrendTransaction]
}

private struct DailySummary: Identifiable {
    let date: Date
    let total: Int
    let count: Int
    let memoCount: Int

    var id: Date { date }
}

private struct DailyCategorySummary: Identifiable {
    let categoryName: String
    let amount: Int
    let color: Color

    var id: String { categoryName }
}

struct DailyTrendDetailView: View {
    let context: DailyTrendDetailContext

    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date?

    private var calendar: Calendar { Calendar.current }

    private var summaries: [DailySummary] {
        let groups = Dictionary(grouping: context.transactions) { calendar.startOfDay(for: $0.date) }
        return groups.map { day, txs in
            DailySummary(
                date: day,
                total: txs.reduce(0) { $0 + $1.amount },
                count: txs.count,
                memoCount: txs.filter { !$0.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
            )
        }
        .sorted { $0.date > $1.date }
    }

    private var selectedSummary: DailySummary? {
        guard let day = selectedDate else { return summaries.first }
        return summaries.first(where: { calendar.isDate($0.date, inSameDayAs: day) })
    }

    private var previousSummary: DailySummary? {
        guard let selected = selectedSummary,
              let prev = calendar.date(byAdding: .day, value: -1, to: selected.date)
        else { return nil }
        return summaries.first(where: { calendar.isDate($0.date, inSameDayAs: prev) })
    }

    private var selectedDayCategories: [DailyCategorySummary] {
        guard let selected = selectedSummary else { return [] }
        let dayTxs = context.transactions.filter { calendar.isDate($0.date, inSameDayAs: selected.date) }
        let colorMap = Dictionary(
            context.series.map { ($0.categoryName, $0.color) },
            uniquingKeysWith: { first, _ in first }
        )
        let grouped = Dictionary(grouping: dayTxs, by: { $0.categoryName })

        return grouped.map { name, txs in
            DailyCategorySummary(
                categoryName: name,
                amount: txs.reduce(0) { $0 + $1.amount },
                color: colorMap[name] ?? .gray
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private var selectedDayTransactions: [DailyTrendTransaction] {
        guard let selected = selectedSummary else { return [] }
        return context.transactions
            .filter { calendar.isDate($0.date, inSameDayAs: selected.date) }
            .sorted { $0.amount > $1.amount }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    chartCard
                    summaryCard
                    categoryCard
                    highSpendingCard
                }
                .padding()
            }
            .navigationTitle("日別推移の詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear {
                selectedDate = summaries.first?.date
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(context.title)
                .font(.headline)
            Text("日付をタップすると、その日の内訳を確認できます")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(context.series) { point in
                BarMark(
                    x: .value("日", point.date, unit: .day),
                    y: .value("金額", point.amount)
                )
                .foregroundStyle(point.color)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisTick()
                    AxisValueLabel(format: .dateTime.day().locale(Locale(identifier: "ja_JP")))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisTick()
                    AxisValueLabel {
                        if let amount = value.as(Int.self) {
                            Text(currency(amount))
                        }
                    }
                }
            }
            .frame(height: 200)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(summaries) { summary in
                        let selected = calendar.isDate(summary.date, inSameDayAs: selectedSummary?.date ?? summary.date)
                        Button {
                            selectedDate = summary.date
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(dayText(summary.date))
                                    .font(.caption.weight(.semibold))
                                Text(currency(summary.total))
                                    .font(.caption2)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("選択日のサマリー")
                .font(.headline)

            if let selected = selectedSummary {
                metricRow(title: "合計支出", value: currency(selected.total))
                metricRow(title: "件数", value: "\(selected.count)件")
                metricRow(title: "1件あたり", value: currency(selected.total / max(selected.count, 1)))
                metricRow(title: "メモ付き", value: "\(selected.memoCount)件")

                if let previous = previousSummary {
                    let diff = selected.total - previous.total
                    let prefix = diff >= 0 ? "+" : ""
                    metricRow(title: "前日比", value: "\(prefix)\(currency(diff))")
                }
            } else {
                Text("表示できるデータがありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("カテゴリ内訳")
                .font(.headline)

            if let total = selectedSummary?.total, total > 0 {
                ForEach(selectedDayCategories.prefix(5)) { category in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Circle()
                                .fill(category.color)
                                .frame(width: 8, height: 8)
                            Text(category.categoryName)
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(Double(category.amount) / Double(total) * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(currency(category.amount))
                                .font(.subheadline.weight(.semibold))
                        }
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.12))
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(category.color)
                                        .frame(width: max(4, proxy.size.width * CGFloat(category.amount) / CGFloat(total)))
                                }
                        }
                        .frame(height: 6)
                    }
                }
            } else {
                Text("カテゴリ内訳を表示できる支出がありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
    }

    private var highSpendingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("この日の高額支出")
                .font(.headline)

            ForEach(selectedDayTransactions.prefix(3)) { tx in
                HStack(spacing: 8) {
                    Text(tx.categoryName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                    Text(currency(tx.amount))
                        .font(.subheadline.weight(.semibold))
                }
                if !tx.memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(tx.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Divider()
            }

            if selectedDayTransactions.isEmpty {
                Text("高額支出を表示できるデータがありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
    }

    @ViewBuilder
    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
    }

    private func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d(EEE)"
        return formatter.string(from: date)
    }

    private func currency(_ n: Int) -> String {
        let absValue = abs(n)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        let body = formatter.string(from: NSNumber(value: absValue)) ?? "\(absValue)"
        return n < 0 ? "-¥\(body)" : "¥\(body)"
    }
}
