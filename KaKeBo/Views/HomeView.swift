import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // ① 月次ヘッダー（収支・支出・収入）
                    MonthlyHeaderCard(
                        income: monthIncome,
                        expense: monthExpense,
                        balance: monthBalance
                    )
                    
                    // ② 円グラフ：カテゴリ別支出比率（当月）
                    if !categoryBreakdown.isEmpty {
                        CategoryDonutChart(breakdown: categoryBreakdown)
                            .luxCard()
                            .padding(.horizontal)
                    }
                    
                    // ③ 棒グラフ：日別推移（当月）
                    if !dailySeries.isEmpty {
                        DailyBarChart(series: dailySeries)
                            .luxCard()
                            .padding(.horizontal)
                    }
                    
                    // ④ 最近の取引
                    RecentTransactionsSection(transactions: recentTransactions, categories: store.categories)
                        .luxCard()
                        .padding(.horizontal)
                    
                    Spacer(minLength: 24)
                }
                .padding(.top, 12)
            }
            .background(
                LinearGradient(
                    colors: scheme == .dark
                    ? [Color.black, Color(white: 0.15)]
                    : [Color(white: 0.98), Color(white: 0.94)],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()
            )
            .navigationTitle("ホーム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("新規追加")
                }
            }
            .sheet(isPresented: $showAdd) {
                AddTransactionView(defaultCategoryId: store.categories.first?.id)
                    .environmentObject(store)
            }
        }
    }
}

// MARK: - 集計ヘルパ
extension HomeView {
    private var thisMonthTx: [Transaction] {
        let cal = Calendar.current
        let now = Date()
        return store.transactions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
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
    
    // 円グラフ用：カテゴリ別支出合計（当月）
    private var categoryBreakdown: [CategorySlice] {
        let expenseTx = thisMonthTx.filter { $0.type == .expense }
        var dict: [UUID: Int] = [:]
        for tx in expenseTx {
            dict[tx.categoryId, default: 0] += tx.amount
        }
        // モデルからカテゴリ名と色を引く
        return dict.compactMap { (catId, sum) in
            guard let cat = store.categories.first(where: { $0.id == catId }) else { return nil }
            return CategorySlice(id: catId, name: cat.name, color: cat.color, value: sum)
        }
        .sorted { $0.value > $1.value }
    }
    
    // 棒グラフ用：日別支出（当月）
    private var dailySeries: [DailyPoint] {
        let cal = Calendar.current
        let expenseTx = thisMonthTx.filter { $0.type == .expense }
        var dict: [Date: Int] = [:]
        for tx in expenseTx {
            // 日単位で揃える（時刻を落とす）
            let day = cal.startOfDay(for: tx.date)
            dict[day, default: 0] += tx.amount
        }
        return dict.keys.sorted().map { day in
            DailyPoint(date: day, amount: dict[day] ?? 0)
        }
    }
    
    // 最近の取引（最大10件）
    private var recentTransactions: [Transaction] {
        store.transactions.sorted { $0.date > $1.date }.prefix(10).map { $0 }
    }
}
