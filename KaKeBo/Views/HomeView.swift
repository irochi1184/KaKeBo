//
//  Views/HomeView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var hSize   // ← 追加！
    
    // ← 追加：選択中の月（常に月初に正規化して扱う）
    @State private var selectedMonth: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Date()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // 月次ヘッダー（収支・支出・収入）
                    MonthlyHeaderCard(
                        income: monthIncome,
                        expense: monthExpense,
                        balance: monthBalance
                    )
                    .padding(.horizontal)
                    
                    // 円グラフ：カテゴリ別支出比率（選択月）
                    if !expenseBreakdown.isEmpty {
                        CategoryDonutPager(
                            expense: expenseBreakdown,                    // 既存の支出ブレイクダウン
                            expenseCurrentTotal: monthExpense,            // 今月の支出合計
                            expensePreviousTotal: prevMonthExpense,       // 先月の支出合計
                            income: incomeBreakdown,                      // 新規：収入ブレイクダウン
                            incomeCurrentTotal: monthIncome,              // 今月の収入合計
                            incomePreviousTotal: prevMonthIncome          // 先月の収入合計
                        )
                        .glassCard()
                        .padding(.horizontal)
                    }
                    
                    // 棒グラフ：日別推移（選択月）
                    if !dailySeries.isEmpty {
                        DailyBarChart(series: dailySeries)
                            .luxCard()
                            .padding(.horizontal)
                    }
                    
                    // 最近の取引（選択月から）
                    RecentTransactionsSection(transactions: recentTransactions, categories: store.categories)
                        .luxCard()
                        .padding(.horizontal)
                    
                    Spacer(minLength: 24)
                }
                .padding(.top, 0)
            }
            .background(
                LinearGradient(
                    colors: scheme == .dark
                    ? [Color.black, Color(white: 0.15)]
                    : [Color(white: 0.98), Color(white: 0.94)],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    YearMonthHeader(
                        month: $selectedMonth,
                        title: monthTitleForToolbar(selectedMonth, compact: hSize == .compact)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .layoutPriority(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新規追加")
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTransactionView(defaultCategoryId: store.categories.first?.id)
                    .environmentObject(store)
            }
            .onChange(of: selectedMonth) {
                selectedMonth = monthStart(selectedMonth)
            }

        }
    }
}

// MARK: - ヘルパ（選択月に基づく集計）
extension HomeView {
    private var thisMonthTx: [Transaction] {
        let cal = Calendar.current
        return store.transactions.filter { cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
    }
    
    private var monthIncome: Int {
        thisMonthTx.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }
    private var monthExpense: Int {
        thisMonthTx.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    private var monthBalance: Int {
        monthIncome - monthExpense
    }
    
    // 円グラフ：カテゴリ別支出（選択月）
    private var expenseBreakdown: [CategorySlice] {
        let cal = Calendar.current
        let expenseTx = store.transactions.filter {
            $0.type == .expense && cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
        var dict: [UUID: Int] = [:]
        for tx in expenseTx { dict[tx.categoryId, default: 0] += tx.amount }
        return dict.compactMap { (catId, sum) in
            guard let cat = store.categories.first(where: { $0.id == catId }) else { return nil }
            return CategorySlice(id: catId, name: cat.name, color: cat.color, value: sum)
        }
        .sorted { $0.value > $1.value }
    }
    
    private var incomeBreakdown: [CategorySlice] {
        let cal = Calendar.current
        let tx = store.transactions.filter { $0.type == .income && cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
        var dict: [UUID: Int] = [:]
        tx.forEach { dict[$0.categoryId, default: 0] += $0.amount }
        return dict.compactMap { (id, sum) in
            guard let cat = store.categories.first(where: { $0.id == id }) else { return nil }
            return CategorySlice(id: id, name: cat.name, color: cat.color, value: sum)
        }.sorted { $0.value > $1.value }
    }

    
    // 棒グラフ：日別支出（選択月）
    private var dailySeries: [DailyPoint] {
        let cal = Calendar.current
        let expenseTx = store.transactions.filter {
            $0.type == .expense && cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month)
        }
        var dict: [Date: Int] = [:]
        for tx in expenseTx {
            let day = cal.startOfDay(for: tx.date)
            dict[day, default: 0] += tx.amount
        }
        return dict.keys.sorted().map { day in DailyPoint(date: day, amount: dict[day] ?? 0) }
    }
    
    // 最近の取引（選択月から上位10件）
    private var recentTransactions: [Transaction] {
        let cal = Calendar.current
        return store.transactions
            .filter { cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
            .sorted { $0.date > $1.date }
            .prefix(10)
            .map { $0 }
    }
    
    // 表示用
    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }
    private func monthStart(_ date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }
    private func monthTitleForToolbar(_ date: Date, compact: Bool) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }

    private var prevMonthExpense: Int {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        return store.transactions
            .filter { $0.type == .expense && cal.isDate($0.date, equalTo: prev, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }
    
    private var prevMonthIncome: Int {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        return store.transactions
            .filter { $0.type == .income && cal.isDate($0.date, equalTo: prev, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
    }
}
