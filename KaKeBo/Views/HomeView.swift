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
    @EnvironmentObject var themeStore: ThemeStore
    @State private var showAdd = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    
    @State private var selectedMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([ .year, .month ], from: Date())
        return cal.date(from: comps) ?? Date()
    }()
    @State private var editingTx: Transaction? = nil
    
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
                    .luxCard()
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
                        .luxCard()
                        .padding(.horizontal)
                    }
                    
                    // 棒グラフ：日別推移（選択月）
                    if !dailySeries.isEmpty {
                        DailyBarChart(series: dailySeries)
                            .luxCard()
                            .padding(.horizontal)
                    }
                    
                    // 最近の取引（選択月から）
                    if !allThisMonthTransactions.isEmpty {
                        TransactionListCard(
                            transactions: allThisMonthTransactions,
                            categories: store.categories,
                            onEdit: { tx in editingTx = tx },
                            onDeleteIDs: { ids in
                                // DataStore に用意（次の項目）
                                store.deleteTransactions(with: ids)
                            }
                        )
                        .luxCard()
                        .padding(.horizontal)
                    }
                    
                    Spacer(minLength: 24)
                }
                .padding(.top, 0)
            }
            .background(
                themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    YearMonthHeader(
                        month: $selectedMonth,
                        title: monthTitleForToolbar(selectedMonth, compact: hSize == .compact),
                        accent: themeStore.theme.accentColor(for: scheme)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .layoutPriority(1)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("新規追加")
                        .tint(themeStore.theme.accentColor(for: scheme))
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTransactionView(defaultCategoryId: store.categories.first?.id)
                    .environmentObject(store)
            }
            .sheet(item: $editingTx) { tx in
                EditTransactionView(transaction: tx)    // ← 次で作る編集画面
                    .environmentObject(store)
            }

            .onChange(of: selectedMonth) {
                selectedMonth = monthStart(selectedMonth)
            }

        }.onAppear {
            store.applyFixedExpensesForCurrentMonth()
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
//    private var recentTransactions: [Transaction] {
//        let cal = Calendar.current
//        return store.transactions
//            .filter { cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
//            .sorted { $0.date > $1.date }
//            .prefix(10)
//            .map { $0 }
//    }
    private var allThisMonthTransactions: [Transaction] {
        let cal = Calendar.current
        return store.transactions
            .filter { cal.isDate($0.date, equalTo: selectedMonth, toGranularity: .month) }
            .sorted { $0.date > $1.date }
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

private struct TransactionRow: View {
    let tx: Transaction
    let category: Category
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(category.color.opacity(0.12))
                Image(systemName: category.symbolName)
                    .foregroundStyle(category.color)
            }
            .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(.subheadline.weight(.medium))
                if !tx.memo.isEmpty {
                    Text(tx.memo).font(.caption).foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(currency(tx.amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tx.type == .income ? .green : .primary)
                Text(dateStr(tx.date))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(EEE)"
        return f.string(from: d)
    }
}

private struct TransactionListCard: View {
    let transactions: [Transaction]
    let categories: [Category]
    let onEdit: (Transaction) -> Void
    let onDeleteIDs: ([UUID]) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("履歴")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            // ← List の代わりに LazyVStack
            LazyVStack(spacing: 0) {
                ForEach(transactions, id: \.id) { tx in
                    if let cat = categories.first(where: { $0.id == tx.categoryId }) {
                        Button { onEdit(tx) } label: {
                            TransactionRow(tx: tx, category: cat)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(.thinMaterial) // なくてもOK
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDeleteIDs([tx.id])
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                        
                        Divider().opacity(0.12)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }
}
