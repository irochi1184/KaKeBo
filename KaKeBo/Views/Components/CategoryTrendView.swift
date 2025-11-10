//
//  Views/Components/CategoryTrendView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/29.
//

import SwiftUI
import Charts

struct CategoryTrendView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    
    let year: Int
    let initialCategoryIds: [UUID]
    
    @State private var selectedIds: Set<UUID> = []
    @State private var stacked: Bool = false          // false=横並び, true=積み上げ
    @State private var showPicker = false
    
    private var accent: Color { themeStore.theme.accentColor(for: scheme) }
    private var background: Color { themeStore.theme.backgroundColor(for: scheme) }
    
    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                headerView
                chipsView
                chartContainer()
                insightsSection
                categoryShareSection
                topTransactionsSection
            }
            .padding()
        }
        .background(background.ignoresSafeArea())
        .navigationTitle("カテゴリ推移")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selectedIds = Set(initialCategoryIds) }
        .sheet(isPresented: $showPicker) {
            CategoryComparePicker(
                allCategories: store.categories,
                selected: $selectedIds,
                accent: accent
            )
            .presentationDetents([.medium, .large])
        }
        // iOS17+: 過剰表示時のみバウンス
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

// MARK: - Subviews

private extension CategoryTrendView {
    var headerView: some View {
        HStack {
            Text("\(String(year))年 カテゴリ推移")
                .font(.headline)
            Spacer()
            Toggle(isOn: $stacked) {
                Text(stacked ? "積み上げ" : "並列")
            }
            .labelsHidden()
            .tint(accent)
            
            Button {
                showPicker = true
            } label: {
                Label("比較を追加", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
            .tint(accent)
        }
    }
    
    var chipsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(selectedCategories) { c in
                    HStack(spacing: 6) {
                        Circle().fill(c.color).frame(width: 10, height: 10)
                        Text(c.name).font(.caption)
                        Button {
                            selectedIds.remove(c.id)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(c.color.opacity(0.08)))
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
    }
    
    @ViewBuilder
    func chartContainer() -> some View {
        let categories: [CategoryDisplay] = selectedCategories
        let rows: [ChartRow] = chartRows
        let xDomain: [String] = Array(1...12).map(String.init)
        
        // ---- 横スクロール幅（カテゴリ増えるほど広げる）
        let catCount: Int = max(1, categories.count)
        let perMonthMin: CGFloat = 36
        let perCategoryAdd: CGFloat = 24
        let perMonthWidth: CGFloat = stacked
        ? perMonthMin
        : perMonthMin + perCategoryAdd * CGFloat(catCount - 1)
        let chartWidth: CGFloat = perMonthWidth * 12 + 24
        
        // ---- Y最大値
        let maxY: Double = computeMaxY(rows: rows, stacked: stacked)
        
        if categories.isEmpty {
            ContentUnavailableView(
                "カテゴリが選択されていません",
                systemImage: "slider.horizontal.3",
                description: Text("「比較を追加」からカテゴリを選んでください")
            )
            .frame(height: 280)
            .background(background)
        } else {
            ScrollView(.horizontal) {
                Group {
                    if stacked {
                        stackedChartView(
                            rows: rows,
                            categories: categories,
                            xDomain: xDomain,
                            maxY: maxY
                        )
                    } else {
                        unstackedChartView(
                            rows: rows,
                            xDomain: xDomain,
                            maxY: maxY,
                            categories: categories
                        )
                    }
                }
                .frame(width: max(chartWidth, 360), height: 280)
                .padding(.trailing, 12)
                .background(background)
            }
        }
    }
    
    // 横並び（クラスタ）
    func unstackedChartView(
        rows: [ChartRow],
        xDomain: [String],
        maxY: Double,
        categories: [CategoryDisplay]
    ) -> some View {
        Chart {
            ForEach(rows) { row in
                BarMark(
                    x: .value("月", String(row.month)),
                    y: .value("金額", row.amount)
                )
                .foregroundStyle(by: .value("カテゴリ", row.categoryKey))
                .position(by: .value("カテゴリ", row.categoryKey))
            }
        }
        .modifier(StyleScaleIfNeeded(
            domain: categories.map { $0.key },
            range: categories.map { $0.color }
        ))
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...maxY)
        .chartXAxis { AxisMarks(values: xDomain) }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartLegend(.hidden)
        // プロット領域は透過、外側は親で背景付与
        .chartPlotStyle { plot in
            plot.background(.clear)
        }
        .background(Color.clear)
    }
    
    // 積み上げ（yStart / yEnd 手動計算）
    func stackedChartView(
        rows: [ChartRow],
        categories: [CategoryDisplay],
        xDomain: [String],
        maxY: Double
    ) -> some View {
        let orderKeys: [String] = categories.map { $0.key }
        let sRows: [StackedRow] = makeStackedRows(rows: rows, orderKeys: orderKeys)
        
        return Chart {
            ForEach(sRows) { r in
                BarMark(
                    x: .value("月", r.monthLabel),
                    yStart: .value("下端", r.yStart),
                    yEnd: .value("上端", r.yEnd)
                )
                .foregroundStyle(by: .value("カテゴリ", r.categoryKey))
            }
        }
        .modifier(StyleScaleIfNeeded(
            domain: categories.map { $0.key },
            range: categories.map { $0.color }
        ))
        .chartXScale(domain: xDomain)
        .chartYScale(domain: 0...maxY)
        .chartXAxis { AxisMarks(values: xDomain) }
        .chartYAxis { AxisMarks(position: .leading) }
        .chartLegend(.hidden)
        .chartPlotStyle { plot in
            plot.background(.clear)
        }
        .background(Color.clear)
    }
}

// MARK: - 補助データ

private extension CategoryTrendView {
    var selectedCategories: [CategoryDisplay] {
        let filtered: [Category] = store.categories.filter { selectedIds.contains($0.id) }
        return filtered.map {
            CategoryDisplay(id: $0.id, key: $0.id.uuidString, name: $0.name, color: $0.color)
        }
    }
    
    var chartRows: [ChartRow] {
        var rows: [ChartRow] = []
        let cal = Calendar.current
        let selected: [Category] = store.categories.filter { selectedIds.contains($0.id) }
        
        for cat in selected {
            var monthly: [Int] = Array(repeating: 0, count: 12)
            for t in store.transactions {
                guard t.categoryId == cat.id, t.type == .expense else { continue }
                let y = cal.component(.year, from: t.date)
                let m = cal.component(.month, from: t.date)
                if y == year, (1...12).contains(m) {
                    monthly[m - 1] += t.amount
                }
            }
            let key: String = cat.id.uuidString
            for m in 1...12 {
                rows.append(ChartRow(month: m, amount: monthly[m - 1], categoryKey: key))
            }
        }
        return rows
    }
    
    func computeMaxY(rows: [ChartRow], stacked: Bool) -> Double {
        guard !rows.isEmpty else { return 1 }
        if stacked {
            // 月ごと合計の最大
            var monthlySum: [Int] = Array(repeating: 0, count: 12)
            for r in rows {
                let idx = max(0, min(11, r.month - 1))
                monthlySum[idx] += r.amount
            }
            let v: Int = monthlySum.max() ?? 0
            return max(1, Double(v))
        } else {
            let v: Int = rows.map(\.amount).max() ?? 0
            return max(1, Double(v))
        }
    }
    
    // 積み上げ用に yStart / yEnd を計算（キー順で累積）
    func makeStackedRows(rows: [ChartRow], orderKeys: [String]) -> [StackedRow] {
        let grouped: [Int: [ChartRow]] = Dictionary(grouping: rows, by: { $0.month })
        var out: [StackedRow] = []
        out.reserveCapacity(rows.count)
        
        for month in 1...12 {
            guard let list = grouped[month], !list.isEmpty else { continue }
            let ordered: [ChartRow] = list.sorted {
                (orderKeys.firstIndex(of: $0.categoryKey) ?? .max)
                < (orderKeys.firstIndex(of: $1.categoryKey) ?? .max)
            }
            var acc: Double = 0
            for item in ordered {
                let start = acc
                let end = acc + Double(item.amount)
                out.append(StackedRow(
                    id: UUID(),
                    month: month,
                    monthLabel: String(month),
                    categoryKey: item.categoryKey,
                    yStart: start,
                    yEnd: end
                ))
                acc = end
            }
        }
        return out
    }
}

// MARK: - モデル

private struct CategoryDisplay: Identifiable, Hashable {
    let id: UUID
    let key: String    // 色・識別用（UUID文字列）
    let name: String   // UI表示用
    let color: Color
}

private struct ChartRow: Identifiable {
    let id = UUID()
    let month: Int
    let amount: Int
    let categoryKey: String  // UUID文字列
}

private struct StackedRow: Identifiable {
    let id: UUID
    let month: Int
    let monthLabel: String
    let categoryKey: String
    let yStart: Double
    let yEnd: Double
}

// MARK: - ForegroundStyle安全適用

private struct StyleScaleIfNeeded: ViewModifier {
    let domain: [String]
    let range: [Color]
    func body(content: Content) -> some View {
        if domain.isEmpty || range.isEmpty {
            content
        } else {
            content.chartForegroundStyleScale(domain: domain, range: range)
        }
    }
}

// MARK: - Picker

private struct CategoryComparePicker: View {
    let allCategories: [Category]
    @Binding var selected: Set<UUID>
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(allCategories, id: \.id) { cat in
                    HStack {
                        Button {
                            if selected.contains(cat.id) { selected.remove(cat.id) }
                            else { selected.insert(cat.id) }
                        } label: {
                            Image(systemName: selected.contains(cat.id) ? "checkmark.square.fill" : "square")
                                .foregroundStyle(selected.contains(cat.id) ? cat.color : .secondary)
                        }
                        .buttonStyle(.plain)
                        Label(cat.name, systemImage: cat.symbolName)
                            .foregroundStyle(cat.color)
                    }
                }
            }
            .navigationTitle("比較するカテゴリ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("適用") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                }
            }
        }
    }
}

// MARK: - Insights Sections

private extension CategoryTrendView {
    
    // 年間サマリ（合計 / 平均 / ベスト・ワースト月）
    var insightsSection: some View {
        let total = totalSelectedYear
        let avg   = total / 12
        let bm    = bestMonthSummary
        let wm    = worstMonthSummary
        
        return VStack(spacing: 10) {
            Text("年間サマリ")
                .font(.headline)
            
            HStack(spacing: 12) {
                InsightCard(title: "合計", value: yen(total), tint: .blue)
                InsightCard(title: "月平均", value: yen(avg), tint: .purple)
                InsightCard(
                    title: "支出最大月",
                    value: bm != nil ? "\(bm!.month)月 \(yen(bm!.amount))" : "-",
                    tint: .green
                )
                InsightCard(
                    title: "支出最小月",
                    value: wm != nil ? "\(wm!.month)月 \(yen(wm!.amount))" : "-",
                    tint: .orange
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.secondary.opacity(0.08))
        )
    }
    
    // カテゴリ別シェア（選択カテゴリのみ）
    var categoryShareSection: some View {
        let shares = categoryShares // [(name, color, amount, ratio 0...1)]
        guard !shares.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("カテゴリ別シェア")
                    .font(.headline)
                
                VStack(spacing: 8) {
                    ForEach(shares, id: \.name) { s in
                        VStack(spacing: 6) {
                            HStack {
                                HStack(spacing: 8) {
                                    Circle().fill(s.color).frame(width: 10, height: 10)
                                    Text(s.name).font(.subheadline)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text("\(Int(round(s.ratio*100)))%  \(yen(s.amount))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            ShareBar(ratio: s.ratio, color: s.color)
                                .frame(height: 8)
                        }
                    }
                }
                .padding(.top, 2)
            }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.secondary.opacity(0.06))
                )
        )
    }
    
    // 高額トップ5明細（選択カテゴリ・対象年）
    var topTransactionsSection: some View {
        let top5 = topTransactions
        guard !top5.isEmpty else { return AnyView(EmptyView()) }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text("高額トップ5（選択カテゴリ・\(String(year))年）")
                    .font(.headline)
                
                VStack(spacing: 8) {
                    ForEach(top5.indices, id: \.self) { i in
                        let t = top5[i]
                        HStack(alignment: .top, spacing: 10) {
                            Text("#\(i+1)")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .leading)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(yen(t.amount))
                                    .font(.subheadline.weight(.semibold))
                                Text("\(dateString(t.date)) ・ \(t.categoryName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !t.memo.isEmpty {
                                    Text(t.memo)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                        
                        if i < top5.count - 1 {
                            Divider().opacity(0.2)
                        }
                    }
                }
                .padding(.top, 2)
            }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.secondary.opacity(0.06))
                )
        )
    }
}

// 小さなカード
private struct InsightCard: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 10).weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.15)))
    }
}

// MARK: - Insights Data Calculations
private extension CategoryTrendView {
    
    var totalSelectedYear: Int {
        let cal = Calendar.current
        return store.transactions.filter { t in
            t.type == .expense &&
            selectedIds.contains(t.categoryId) &&
            cal.component(.year, from: t.date) == year
        }
        .reduce(0) { $0 + $1.amount }
    }
    
    // 月別合計（選択カテゴリの合算）
    var monthlyTotals: [Int] {
        var bins = Array(repeating: 0, count: 12)
        let cal = Calendar.current
        for t in store.transactions where t.type == .expense && selectedIds.contains(t.categoryId) {
            let y = cal.component(.year, from: t.date)
            let m = cal.component(.month, from: t.date)
            if y == year, (1...12).contains(m) {
                bins[m-1] += t.amount
            }
        }
        return bins
    }
    
    var bestMonthSummary: (month: Int, amount: Int)? {
        guard let maxVal = monthlyTotals.max(), maxVal > 0,
              let idx = monthlyTotals.firstIndex(of: maxVal) else { return nil }
        return (idx+1, maxVal)
    }
    
    var worstMonthSummary: (month: Int, amount: Int)? {
        // “0円月” を含めると毎回 0 が最小になるので、0以外の最小にする
        let nonZero = monthlyTotals.enumerated().filter { $0.element > 0 }
        guard let minPair = nonZero.min(by: { $0.element < $1.element }) else { return nil }
        return (minPair.offset + 1, minPair.element)
    }
    
    // カテゴリ別シェア
    // 戻り値: (name, color, amount, ratio)
    var categoryShares: [(name: String, color: Color, amount: Int, ratio: CGFloat)] {
        let cal = Calendar.current
        let cats = store.categories.filter { selectedIds.contains($0.id) }
        let totals: [(Category, Int)] = cats.map { cat in
            let sum = store.transactions.filter { t in
                t.type == .expense &&
                t.categoryId == cat.id &&
                cal.component(.year, from: t.date) == year
            }
                .reduce(0) { $0 + $1.amount }
            return (cat, sum)
        }
        let grand = max(1, totals.reduce(0) { $0 + $1.1 })
        return totals
            .sorted { $0.1 > $1.1 }
            .map { (cat, amt) in
                (cat.name, cat.color, amt, CGFloat(amt) / CGFloat(grand))
            }
    }
    
    // トップ5明細（選択カテゴリ × 対象年）
    var topTransactions: [(amount: Int, date: Date, memo: String, categoryName: String)] {
        let cal = Calendar.current
        let selectedSet = Set(selectedIds)
        let nameById = Dictionary(uniqueKeysWithValues: store.categories.map { ($0.id, $0.name) })
        
        let filtered = store.transactions.filter { t in
            t.type == .expense &&
            selectedSet.contains(t.categoryId) &&
            cal.component(.year, from: t.date) == year
        }
        
        return filtered
            .sorted { $0.amount > $1.amount }
            .prefix(5)
            .map { t in
                (t.amount, t.date, t.memo, nameById[t.categoryId] ?? "-")
            }
    }
    
    func dateString(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "ja_JP")
        df.dateFormat = "M/d"
        return df.string(from: d)
    }
    
    func yen(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}

private struct ShareBar: View {
    let ratio: CGFloat   // 0...1 を想定
    let color: Color
    
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            // 0...1 にクランプし、端数切り上げで端まで届かせる
            let filled = (max(0, min(1, ratio)) * w).rounded(.up)
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.15))
                
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.85))
                    .frame(width: filled)
            }
        }
    }
}
