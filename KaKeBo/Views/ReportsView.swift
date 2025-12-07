//
//  Views/ReportsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/30.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers
import CloudKit

struct YoYSummary {
    let incomeDiff: Int
    let expenseDiff: Int
    let balanceDiff: Int
}

struct ReportsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @Environment(\.colorScheme) private var scheme
    
    // 表示対象の年（初期は今年）
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    // グラフの表示モード（見やすさ切替）
    @State private var stackedBars: Bool = true
    @State private var excludedCategoryIds: Set<String> = []
    @State private var trendTarget: CategoryAnnual? = nil
    
    var body: some View {
        let accent = themeStore.theme.accentColor(for: scheme)
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // MARK: KPI Card
                    KPIHeader(
                        income: yearIncome,
                        expense: yearExpense,
                        balance: yearBalance,
                        savingsRate: yearSavingsRate,
                        avgExpense: avgExpensePerMonth
                    )
                    .luxCard()
                    .padding(.horizontal)
                    
                    // MARK: 月別 収入/支出 バー + 累積残高 ライン
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("月別サマリ").font(.headline)
                            Spacer()
                            Toggle(isOn: $stackedBars) {
                                Text(stackedBars ? "積み上げ" : "並列")
                            }
                            .tint(accent)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                        .padding(.horizontal, 4)
                        
                        MonthlyBarsAndCumLine(
                            monthlyIncome: monthlyIncome,
                            monthlyExpense: monthlyExpense,
                            stacked: stackedBars,
                            accent: accent
                        )
                        .frame(height: 240)
                    }
                    .cardBackground(scheme)
                    
                    // MARK: カテゴリ内訳（支出）
                    // 例：しきい値をここで定義（内側注釈は8%以上の扇だけ）
                    // 例：しきい値
                    let insideThreshold = 0.08
                    
                    if !categoryTotals.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("年間カテゴリ別内訳（支出）").font(.headline)
                            
                            // ★ フィルタ済みを渡す
                            CategoryDonutAnnual(breakdown: filteredCategoryTotals, insideThreshold: insideThreshold)
                                .frame(height: 240)
                            
                            // ★ リスト（全カテゴリを表示しつつ、除外は薄く）
                            VStack(spacing: 8) {
                                ForEach(categoryTotals) { c in
                                    HStack(spacing: 10) {
                                        
                                        // 疑似チェックボックス（現状どおり）
                                        Button {
                                            if excludedCategoryIds.contains(c.id) {
                                                excludedCategoryIds.remove(c.id)
                                            } else {
                                                excludedCategoryIds.insert(c.id)
                                            }
                                        } label: {
                                            Image(systemName: excludedCategoryIds.contains(c.id) ? "square" : "checkmark.square.fill")
                                                .imageScale(.medium)
                                                .foregroundStyle(excludedCategoryIds.contains(c.id) ? .secondary : c.color)
                                                .frame(width: 24)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel(excludedCategoryIds.contains(c.id) ? "含める" : "除外する")
                                        
                                        // ラベル本体（除外時は薄く）
                                        Label(c.name, systemImage: c.symbol)
                                            .labelStyle(.titleAndIcon)
                                            .foregroundStyle(c.color.opacity(excludedCategoryIds.contains(c.id) ? 0.35 : 1.0))
                                        
                                        Spacer()
                                        
                                        Text(yen(c.amount))
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(excludedCategoryIds.contains(c.id) ? .secondary : .primary)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())                // ← 行全体をタップ領域に
                                    .onTapGesture {
                                        guard c.trendCategoryId != nil else { return }
                                        trendTarget = c
                                    }         // ← 行タップで詳細へ
                                    Divider().opacity(0.2)
                                }
                            }
                            .padding(.top, 4)
                            
                            // 便利ボタン（任意）：全選択/全解除
                            HStack(spacing: 12) {
                                Button("全て含める") {
                                    excludedCategoryIds.removeAll()
                                }
                                Button("全て除外") {
                                    excludedCategoryIds = Set(categoryTotals.map { $0.id })
                                }
                                .tint(.secondary)
                                Spacer()
                                // 参考表示：現在の合計
                                let currTotal = filteredCategoryTotals.reduce(0) { $0 + $1.amount }
                                Text("表示合計: \(yen(currTotal))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        }
                        .cardBackground(scheme)
                    }
                    
                    // MARK: ベスト/ワースト月 + 昨年比
                    VStack(spacing: 12) {
                        HStack {
                            Text("ハイライト").font(.headline)
                            Spacer()
                        }
                        
                        HighlightsRow(best: bestMonth, worst: worstMonth)
                        
                        if let y2y = yearOverYear {
                            YoYRow(yoy: y2y)
                        }
                    }
                    .cardBackground(scheme)
                    .padding(.bottom, 24)
                }
            }
            .background(
                themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if ledgerContext.isRestored {
                        LedgerModePicker()
                    }
                }
                ToolbarItem(placement: .principal) {
                        YearPicker(
                            selectedYear: $year,
                            availableYears: availableYears,
                            accent: accent
                        )
                        .tint(accent)
                }
                
                // もし右上に共有ボタン（CSV出力）も置きたいならオプションでこれを追加
                /*
                 ToolbarItem(placement: .topBarTrailing) {
                 ShareLink(
                 item: csvData(),
                 preview: SharePreview("\(String(year))年レポート",
                 image: Image(systemName: "doc"))
                 ) {
                 Image(systemName: "square.and.arrow.up")
                 .font(.headline)
                 }
                 }
                 */
            }

            .navigationDestination(item: $trendTarget) { cat in
                if let trendId = cat.trendCategoryId {
                    CategoryTrendView(
                        year: year,
                        initialCategoryIds: [trendId]
                    )
                    .environmentObject(store)
                    .environmentObject(themeStore)
                    .environmentObject(ledgerContext)
                    .environmentObject(sharedLedgerStore)
                }
            }
            .onAppear {
                // データが今年に無ければ、最新年に寄せる
                if availableYears.contains(year) == false, let latest = availableYears.max() {
                    year = latest
                }
            }
            .task { await reloadSharedLedgerDataIfNeeded() }
            .task(id: ledgerContext.selectedSharedLedgerId) { await reloadSharedLedgerDataIfNeeded() }
            .task(id: ledgerContext.mode) { await reloadSharedLedgerDataIfNeeded() }
            .onChange(of: ledgerContext.selectedSharedLedgerId) { excludedCategoryIds.removeAll() }
            .onChange(of: ledgerContext.mode) { excludedCategoryIds.removeAll() }
            .onChange(of: availableYears) { _, newYears in
                if !newYears.contains(year), let latest = newYears.max() {
                    year = latest
                }
            }
        }
    }
}

// MARK: - UI Parts

private struct YearPicker: View {
    @Binding var selectedYear: Int
    let availableYears: [Int]
    let accent: Color
    
    var body: some View {
        Menu {
            ForEach(availableYears.sorted(by: >), id: \.self) { y in
                Button {
                    selectedYear = y
                } label: {
                    Label("\(String(y))年", systemImage: y == selectedYear ? "checkmark" : "calendar")
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                Text(String(selectedYear) + "年")
                    .font(.headline)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accent.opacity(0.15))
            )
        }
    }
}

private struct KPIHeader: View {
    let income: Int
    let expense: Int
    let balance: Int
    let savingsRate: Double
    let avgExpense: Int
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                KPICard(title: "収入", value: yen(income), tint: .green)
                KPICard(title: "支出", value: yen(expense), tint: .red)
                KPICard(title: "収支", value: yen(balance), tint: balance >= 0 ? .blue : .orange)
            }
            HStack(spacing: 12) {
                KPICard(title: "貯蓄率", value: pct(savingsRate), tint: .purple)
                KPICard(title: "平均支出/月", value: yen(avgExpense), tint: .pink)
            }
        }
    }
}

private struct KPICard: View {
    let title: String
    let value: String
    let tint: Color
    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.15), lineWidth: 1)
        )
    }
}

private struct MonthlyBarsAndCumLine: View {
    let monthlyIncome: [Int]   // 1..12
    let monthlyExpense: [Int]  // 1..12
    let stacked: Bool
    let accent: Color
    
    var body: some View {
        Chart {
            // 収入/支出バー
            ForEach(1...12, id: \.self) { m in
                if stacked {
                    BarMark(
                        x: .value("月", m),
                        y: .value("金額", monthlyIncome[m-1])
                    )
                    .foregroundStyle(.green.opacity(0.85))
                    
                    BarMark(
                        x: .value("月", m),
                        y: .value("金額", -monthlyExpense[m-1]) // 下向きで視覚差別化
                    )
                    .foregroundStyle(.red.opacity(0.85))
                } else {
                    BarMark(
                        x: .value("月", Double(m) - 0.2),
                        y: .value("金額", monthlyIncome[m-1]),
                        width: .ratio(0.35)
                    )
                    .foregroundStyle(.green.opacity(0.85))
                    
                    BarMark(
                        x: .value("月", Double(m) + 0.2),
                        y: .value("金額", monthlyExpense[m-1]),
                        width: .ratio(0.35)
                    )
                    .foregroundStyle(.red.opacity(0.85))
                }
            }
            
            // 累積残高ライン（収入-支出の累積）
            let cum = cumulative(monthlyIncome: monthlyIncome, monthlyExpense: monthlyExpense)
            ForEach(1...12, id: \.self) { m in
                LineMark(
                    x: .value("月", m),
                    y: .value("累積残高", cum[m-1])
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 2.0))
                PointMark(
                    x: .value("月", m),
                    y: .value("累積残高", cum[m-1])
                )
                .foregroundStyle(accent)
            }
        }
        .chartXAxis {
            AxisMarks(values: Array(1...12)) { v in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisTick()
                AxisValueLabel { if let m = v.as(Int.self) { Text("\(m)月") } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 6)) { v in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                AxisTick()
                AxisValueLabel {
                    if let val = v.as(Double.self) {
                        Text(yAxisLabel(val))
                    }
                }
            }
        }
    }
    
    private func yAxisLabel(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
    }
    
    private func cumulative(monthlyIncome: [Int], monthlyExpense: [Int]) -> [Int] {
        var res: [Int] = []
        var acc = 0
        for i in 0..<12 {
            acc += (monthlyIncome[i] - monthlyExpense[i])
            res.append(acc)
        }
        return res
    }
}

extension CategoryAnnual: Hashable {
    static func == (lhs: CategoryAnnual, rhs: CategoryAnnual) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// 年間カテゴリ合計
private struct CategoryAnnual: Identifiable {
    let id: String
    let name: String
    let color: Color
    let symbol: String
    let amount: Int
    let trendCategoryId: CategoryTrendKey?
}

private struct CategoryDonutAnnual: View {
    let breakdown: [CategoryAnnual]
    /// 扇内にラベルを出す最小割合（小さい扇は注釈なし）
    let insideThreshold: Double  // 例: 0.08（8%）
    
    private var total: Int { breakdown.reduce(0) { $0 + $1.amount } }
    
    var body: some View {
        ZStack {
            Chart(breakdown, id: \.id) { c in
                let share = Double(c.amount) / max(1.0, Double(total))
                
                SectorMark(
                    angle: .value("金額", c.amount),
                    innerRadius: .ratio(0.6),
                    outerRadius: .ratio(1.0)
                )
                .foregroundStyle(c.color)
                .accessibilityLabel(Text("\(c.name)"))
                .accessibilityValue(Text(yen(c.amount)))
                
                // 十分大きい扇だけ、白い注釈を中に表示
                .annotation(position: .overlay, alignment: .center) {
                    if share >= insideThreshold {
                        VStack(spacing: 2) {
                            Text(c.name)
                                .font(.caption2.weight(.semibold))
                            Text(yen(c.amount))
                                .font(.caption2)
                                .monospacedDigit()
                        }
                        .foregroundStyle(.white) // ← 白文字
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 2).padding(.horizontal, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .shadow(radius: 1)
                        .allowsHitTesting(false)
                    }
                }
            }
            .chartLegend(.hidden)
            
            // 中央の合計は1回だけ
            VStack(spacing: 2) {
                Text("合計").font(.caption2).foregroundStyle(.secondary)
                Text(yen(total)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .allowsHitTesting(false)
        }
    }
}

private struct HighlightsRow: View {
    let best: (month: Int, balance: Int)?
    let worst: (month: Int, balance: Int)?
    
    var body: some View {
        HStack(spacing: 12) {
            HighlightCard(
                title: "ベスト月",
                subtitle: best.map { "\($0.month)月" } ?? "-",
                value: yen(best?.balance ?? 0),
                tint: .green
            )
            HighlightCard(
                title: "ワースト月",
                subtitle: worst.map { "\($0.month)月" } ?? "-",
                value: yen(worst?.balance ?? 0),
                tint: .red
            )
        }
    }
}

private struct HighlightCard: View {
    let title: String
    let subtitle: String
    let value: String
    let tint: Color
    
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Circle().fill(tint.opacity(0.2)).frame(width: 8, height: 8)
            }
            HStack {
                Text(subtitle).font(.subheadline.weight(.medium))
                Spacer()
                Text(value).font(.headline.weight(.semibold)).monospacedDigit()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(tint.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.15)))
        .frame(maxWidth: .infinity)
    }
}

private struct YoYRow: View {
    let yoy: YoYSummary
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("昨年比").font(.headline)
            HStack(spacing: 12) {
                KPIYoY(title: "収入", diff: yoy.incomeDiff)
                KPIYoY(title: "支出", diff: yoy.expenseDiff)
                KPIYoY(title: "収支", diff: yoy.balanceDiff)
            }
        }
    }
}

private struct KPIYoY: View {
    let title: String
    let diff: Int
    var body: some View {
        let up = diff >= 0
        return VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                Text(yen(abs(diff))).monospacedDigit()
            }
            .foregroundStyle(up ? .green : .red)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(.thinMaterial))
    }
}

// MARK: - Style helper
private extension View {
    func cardBackground(_ scheme: ColorScheme) -> some View {
        self
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : .white)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.06), radius: 12, y: 6)
            )
            .padding(.horizontal)
    }
}

// MARK: - Data helpers
private extension ReportsView {
    private enum ReportTransactionType {
        case income
        case expense
    }

    private struct ReportTransaction {
        let date: Date
        let amount: Int
        let type: ReportTransactionType
        let memo: String
        let categoryKey: String
        let categoryName: String
        let color: Color
        let symbol: String
        let trendCategoryId: CategoryTrendKey?
    }

    var availableYears: [Int] {
        let cal = Calendar.current
        let ys = reportTransactions.map { cal.component(.year, from: $0.date) }
        return Array(Set(ys)).sorted()
    }

    private var txThisYear: [ReportTransaction] {
        reportTransactions.filter { Calendar.current.component(.year, from: $0.date) == year }
    }

    var yearIncome: Int {
        txThisYear.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }

    var yearExpense: Int {
        txThisYear.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }

    var yearBalance: Int { yearIncome - yearExpense }

    var yearSavingsRate: Double {
        let inc = Double(yearIncome)
        guard inc > 0 else { return 0 }
        return Double(yearBalance) / inc
    }

    var avgExpensePerMonth: Int {
        // 実データのある月数で割る or 12で割る、好みで。ここは実データ月数
        let usedMonths = Set(txThisYear.map { Calendar.current.component(.month, from: $0.date) })
        let denom = max(usedMonths.count, 1)
        return Int(Double(yearExpense) / Double(denom))
    }

    var monthlyIncome: [Int] {
        (1...12).map { m in
            txThisYear.filter { Calendar.current.component(.month, from: $0.date) == m && $0.type == .income }
                .reduce(0) { $0 + $1.amount }
        }
    }

    var monthlyExpense: [Int] {
        (1...12).map { m in
            txThisYear.filter { Calendar.current.component(.month, from: $0.date) == m && $0.type == .expense }
                .reduce(0) { $0 + $1.amount }
        }
    }

    var bestMonth: (month: Int, balance: Int)? {
        let balances = (1...12).map { m -> (Int, Int) in
            let inc = txThisYear.filter { Calendar.current.component(.month, from: $0.date) == m && $0.type == .income }.reduce(0){$0+$1.amount}
            let exp = txThisYear.filter { Calendar.current.component(.month, from: $0.date) == m && $0.type == .expense }.reduce(0){$0+$1.amount}
            return (m, inc - exp)
        }
        return balances.max(by: { $0.1 < $1.1 })
    }

    var worstMonth: (month: Int, balance: Int)? {
        let balances = (1...12).map { m -> (Int, Int) in
            let inc = txThisYear.filter { Calendar.current.component(.month, from: $0.date) == m && $0.type == .income }.reduce(0){$0+$1.amount}
            let exp = txThisYear.filter { Calendar.current.component(.month, from: $0.date) == m && $0.type == .expense }.reduce(0){$0+$1.amount}
            return (m, inc - exp)
        }
        return balances.min(by: { $0.1 < $1.1 })
    }

    var categoryTotals: [CategoryAnnual] {
        // 年間の支出カテゴリ合計
        var dict: [String: (total: Int, trendId: CategoryTrendKey?, sample: ReportTransaction?)] = [:]
        for tx in txThisYear where tx.type == .expense {
            let key = tx.categoryKey
            var entry = dict[key] ?? (0, tx.trendCategoryId, tx)
            entry.total += tx.amount
            entry.trendId = tx.trendCategoryId
            entry.sample = tx
            dict[key] = entry
        }
        return dict.compactMap { (_, value) in
            guard let sample = value.sample else { return nil }
            return CategoryAnnual(
                id: sample.categoryKey,
                name: sample.categoryName,
                color: sample.color,
                symbol: sample.symbol,
                amount: value.total,
                trendCategoryId: value.trendId
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    var yearOverYear: YoYSummary? {
        let prev = year - 1
        guard availableYears.contains(prev) else { return nil }

        let cal = Calendar.current
        let thisY = reportTransactions.filter { cal.component(.year, from: $0.date) == year }
        let lastY = reportTransactions.filter { cal.component(.year, from: $0.date) == prev }

        let incThis = thisY.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expThis = thisY.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let balThis = incThis - expThis

        let incPrev = lastY.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let expPrev = lastY.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let balPrev = incPrev - expPrev

        return .init(
            incomeDiff: incThis - incPrev,
            expenseDiff: expThis - expPrev,
            balanceDiff: balThis - balPrev
        )
    }

    // CSV Export（年/月/カテゴリ/タイプ/金額/メモ/日付）
    func csvData() -> ShareableResource {
        let cal = Calendar.current
        let rows: [[String]] = reportTransactions
            .filter { cal.component(.year, from: $0.date) == year }
            .sorted { $0.date < $1.date }
            .map { tx in
                let month = cal.component(.month, from: tx.date)
                let type = (tx.type == .income) ? "収入" : "支出"
                let amount = "\(tx.amount)"
                let memo = tx.memo.replacingOccurrences(of: "\"", with: "\"\"")
                let df = DateFormatter()
                df.locale = Locale(identifier: "ja_JP"); df.dateFormat = "yyyy-MM-dd"
                return ["\(year)", "\(month)", "\"\(tx.categoryName)\"", type, amount, "\"\(memo)\"", df.string(from: tx.date)]
            }

        var csv = "year,month,category,type,amount,memo,date\n"
        for r in rows { csv += r.joined(separator: ",") + "\n" }
        let data = csv.data(using: .utf8) ?? Data()
        return ShareableResource(data: data, filename: "KaKeBo_\(year)_report.csv", contentType: .plainText)
    }
    var filteredCategoryTotals: [CategoryAnnual] {
        categoryTotals.filter { !excludedCategoryIds.contains($0.id) }
    }

    private var reportTransactions: [ReportTransaction] {
        if ledgerContext.isShared {
            guard let ledger = currentSharedLedger else { return [] }

            let categories = sharedLedgerStore.categoriesByLedger[ledger.id] ?? []
            let txs = sharedLedgerStore.transactionsByLedger[ledger.id] ?? []
            return txs.map { tx in
                let cat = categories.first { $0.id == tx.categoryId }
                let color = Color.fromHex(cat?.colorHex ?? tx.categoryColorHex) ?? .gray
                return ReportTransaction(
                    date: tx.date,
                    amount: tx.amount,
                    type: tx.type == .income ? .income : .expense,
                    memo: tx.memo ?? "",
                    categoryKey: tx.categoryId?.recordName ?? tx.categoryName,
                    categoryName: cat?.name ?? tx.categoryName,
                    color: color,
                    symbol: cat?.icon ?? "tag.fill",
                    trendCategoryId: tx.categoryId.map { CategoryTrendKey.shared($0) }
                )
            }
        }

        // Personal ledger fallback
        return store.transactions.map { tx in
            let cat = store.categories.first(where: { $0.id == tx.categoryId })
            return ReportTransaction(
                date: tx.date,
                amount: tx.amount,
                type: tx.type == .income ? .income : .expense,
                memo: tx.memo,
                categoryKey: tx.categoryId.uuidString,
                categoryName: cat?.name ?? "未分類",
                color: cat?.color ?? .gray,
                symbol: cat?.symbolName ?? "tag.fill",
                trendCategoryId: cat.map { CategoryTrendKey.personal($0.id) }
            )
        }
    }

    private var currentSharedLedger: SharedLedger? {
        ledgerContext.currentSharedLedger(from: sharedLedgerStore)
    }

    private func reloadSharedLedgerDataIfNeeded() async {
        guard ledgerContext.isShared,
              let ledger = currentSharedLedger else { return }

        await sharedLedgerStore.reloadCategories(for: ledger)
        await sharedLedgerStore.reloadTransactions(for: ledger)
    }
}

// MARK: - Formatting helpers
private func yen(_ n: Int) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
    return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
}
private func pct(_ v: Double) -> String {
    let p = Int(round(v * 100))
    return "\(p)%"
}

// MARK: - Share helper
struct ShareableResource: Transferable, Identifiable {
    let data: Data
    let filename: String
    let contentType: UTType
    var id: String { filename }
    
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { resource in
            resource.data
        }
        .suggestedFileName { resource in resource.filename }
    }
}
