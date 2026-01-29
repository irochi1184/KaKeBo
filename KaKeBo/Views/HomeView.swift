//
//  Views/HomeView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers
import CloudKit

struct HomeView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var monthStartStore: MonthStartStore
    @State private var showAdd = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var didSetInitialMonth = false
    
    // 最後に開いたモード／共有家計簿IDを保存
    @AppStorage("home.lastLedgerMode") private var lastLedgerModeRaw: String = "personal"
    @AppStorage("home.lastSharedLedgerRecordName") private var lastSharedLedgerRecordName: String?
    @AppStorage("monthStart.onboardingDone") private var monthStartOnboardingDone = false
    
    @State private var selectedMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([ .year, .month ], from: Date())
        return cal.date(from: comps) ?? Date()
    }()
    @State private var editingTx: Transaction? = nil
    @State private var editingSharedTx: SharedTransaction? = nil

    @State private var showMonthStartIntro = false
    @State private var breakdownSheet: CategoryBreakdownSheetData?

    // ▼ 追加：カード順序の状態とドラッグ中のカード
    @State private var cardOrder: [DashboardCard] = CardOrderStore().load(default: [.header, .donut, .daily, .transactions])
    @State private var dragging: DashboardCard?

    private let dropUTIs: [UTType] = [.plainText] // onDrag のペイロード種別

    private var monthResolver: MonthStartResolver { monthStartStore.resolver() }

    struct CategoryBreakdownSheetData: Identifiable {
        let id = UUID()
        let title: String
        let breakdown: [CategorySlice]
        let currentTotal: Int
        let previousTotal: Int
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if ledgerContext.isRestored {
                    switch ledgerContext.mode {
                    case .personal:
                        personalContent
                    case .shared:
                        sharedContent
                    }
                } else {
                    // ローディング画面
                    LedgerLoadingView()
                }
            }
            .background(
                themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea()
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if ledgerContext.isRestored {
                    ToolbarItem(placement: .topBarLeading) {
                        LedgerModePicker()
                    }
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
                        let accent = themeStore.theme.accentColor(for: scheme)
                        Button {
                            showAdd = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent.opacity(0.2))
                        .accessibilityLabel("新規追加")
                    }
                }
            }
            // 個人用と共有用は AddTransactionView で判断
            .sheet(isPresented: $showAdd) {
                AddTransactionView(defaultCategoryId: store.categories.first?.id)
                    .environmentObject(store)
            }
            .sheet(item: $editingTx) { tx in
                EditTransactionView(transaction: tx)
                    .environmentObject(store)
            }
            .sheet(item: $editingSharedTx) { tx in
                if let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore) {
                    EditTransactionView(sharedLedger: ledger, transaction: tx)
                        .presentationDetents([.large])
                }
            }
            .onChange(of: selectedMonth) { _, _ in
                selectedMonth = monthStart(selectedMonth)
            }
            .sheet(item: $breakdownSheet) { sheet in
                CategoryBreakdownSheet(
                    title: sheet.title,
                    breakdown: sheet.breakdown,
                    currentTotal: sheet.currentTotal,
                    previousTotal: sheet.previousTotal
                )
                .presentationDetents([.large])
            }
        }
        .onAppear {
            store.applyFixedExpensesForCurrentMonth()
            if !monthStartOnboardingDone {
                showMonthStartIntro = true
            }
            if !didSetInitialMonth {
                selectedMonth = monthResolver.anchorMonth(containing: Date())
                didSetInitialMonth = true
            }
        }
        .task {
            //   LedgerContext に任せる
            await ledgerContext.restoreIfNeeded(sharedLedgerStore: sharedLedgerStore)
        }
    }
    
    @ViewBuilder
    private var personalContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                
                ForEach(visibleCardsInOrder(), id: \.id) { card in
                    reorderableCard(card) {
                        render(card)
                    }
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 24)
            }
            .padding(.top, 0)
            .onDrop(of: dropUTIs, isTargeted: nil, perform: { _ in
                dragging = nil
                return true
            })
        }
    }
    
    @ViewBuilder
    private var sharedContent: some View {
        let ledger: SharedLedger? = ledgerContext.currentSharedLedger(from: sharedLedgerStore)
        
        if let ledger {
            let allTxs = sharedLedgerStore.transactionsByLedger[ledger.id] ?? []
//            let monthTxs = sharedThisMonthTx(allTxs: allTxs)
            let cats   = sharedLedgerStore.categoriesByLedger[ledger.id] ?? []
            let expenseSlices = sharedExpenseBreakdown(allTxs: allTxs, categories: cats)
            let incomeSlices  = sharedIncomeBreakdown(allTxs: allTxs, categories: cats)
            let dailyPoints   = sharedDailySeries(allTxs: allTxs, categories: cats)
            
            ScrollView {
                VStack(spacing: 16) {
                    // ① ヘッダーカード（今月の収支）
                    MonthlyHeaderCard(
                        income: sharedMonthIncome(txs: allTxs),
                        expense: sharedMonthExpense(txs: allTxs),
                        balance: sharedMonthBalance(txs: allTxs)
                    )
                    .homeCard()
                    .padding(.horizontal)
                    
                    // ② カテゴリ別 ドーナツグラフ
                    if !expenseSlices.isEmpty || !incomeSlices.isEmpty {
                        CategoryDonutPager(
                            expense: expenseSlices,
                            expenseCurrentTotal: sharedMonthExpense(txs: allTxs),
                            expensePreviousTotal: sharedPrevMonthExpense(allTxs: allTxs),
                            income: incomeSlices,
                            incomeCurrentTotal: sharedMonthIncome(txs: allTxs),
                            incomePreviousTotal: sharedPrevMonthIncome(allTxs: allTxs)
                        )
                        .homeCard()
                        .padding(.horizontal)
                        .onTapGesture {
                            breakdownSheet = CategoryBreakdownSheetData(
                                title: monthTitle(selectedMonth),
                                breakdown: expenseSlices,
                                currentTotal: sharedMonthExpense(txs: allTxs),
                                previousTotal: sharedPrevMonthExpense(allTxs: allTxs)
                            )
                        }
                    }
                    
                    // ③ 日別棒グラフ
                    if !dailyPoints.isEmpty {
                        DailyBarChart(series: dailyPoints)
                            .homeCard()
                            .padding(.horizontal)
                    }
                    
                    // ④ 当月の履歴リスト
//                    let monthTxs = sharedThisMonthTx(allTxs: allTxs)

                    TransactionListCard(
                        sharedTransactions: allTxs.filter { tx in
                            isInCurrentMonth(tx.date)
                        },
                        categories: cats,
                        onEdit: { tx in editingSharedTx = tx }
                    )
                    .homeCard()
                    .padding(.horizontal)

                    
                    Spacer(minLength: 24)
                }
                .padding(.top, 0)
            }
            .task {
                await sharedLedgerStore.reloadCategories(for: ledger)
                await sharedLedgerStore.reloadTransactions(for: ledger)
            }
            
        } else {
            VStack(spacing: 12) {
                Text("共有家計簿が選択されていません")
                    .font(.headline)
                Text("左上のメニューから共有家計簿を選択、または作成してください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // 現在のデータ状況で表示可能なカードのみを順序通りに返す
    private func visibleCardsInOrder() -> [DashboardCard] {
        cardOrder.filter { c in
            switch c {
            case .header: return true
            case .donut:  return !expenseBreakdown.isEmpty || !incomeBreakdown.isEmpty
            case .daily:  return !dailySeries.isEmpty
            case .transactions: return !allThisMonthTransactions.isEmpty
            }
        }
    }
    
    // カードの実体ビュー（既存のビューをそのまま使う）
    @ViewBuilder
    private func render(_ card: DashboardCard) -> some View {
        switch card {
        case .header:
            MonthlyHeaderCard(
                income: monthIncome,
                expense: monthExpense,
                balance: monthBalance
            )
            .homeCard()
            
        case .donut:
            CategoryDonutPager(
                expense: expenseBreakdown,
                expenseCurrentTotal: monthExpense,
                expensePreviousTotal: prevMonthExpense,
                income: incomeBreakdown,
                incomeCurrentTotal: monthIncome,
                incomePreviousTotal: prevMonthIncome
            )
            .homeCard()
            .onTapGesture {
                breakdownSheet = CategoryBreakdownSheetData(
                    title: monthTitle(selectedMonth),
                    breakdown: expenseBreakdown,
                    currentTotal: monthExpense,
                    previousTotal: prevMonthExpense
                )
            }

        case .daily:
            DailyBarChart(series: dailySeries)
                .homeCard()
            
        case .transactions:
            TransactionListCard(
                transactions: allThisMonthTransactions,
                categories: store.categories,
                onEdit: { tx in editingTx = tx },
                onDeleteIDs: { ids in store.deleteTransactions(with: ids) }
            )
            .homeCard()
        }
    }
    
    // 1カードをドラッグ/ドロップ可能にラップ
    @ViewBuilder
    private func reorderableCard<Content: View>(_ card: DashboardCard, @ViewBuilder content: () -> Content) -> some View {
        @State var isTargeted = false
        
        content()
            .scaleEffect(dragging == card ? 0.98 : 1.0)
            .animation(.snappy(duration: 0.15), value: isTargeted)
            .animation(.snappy(duration: 0.15), value: dragging == card)
        
        // ドラッグ開始
            .onDrag {
                dragging = card
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return NSItemProvider(object: card.id as NSString)
            }
        
        // 自身の上に入ってきたら配列を差し替える
            .onDrop(of: dropUTIs, delegate: CardDropDelegate(
                current: card,
                items: $cardOrder,
                dragging: $dragging,
                onCommit: { CardOrderStore().save(cardOrder) }
            ))
    }
}


// MARK: - ヘルパ（選択月に基づく集計）
extension HomeView {
    private func isInCurrentMonth(_ date: Date) -> Bool {
        monthResolver.contains(date, inMonthOf: selectedMonth)
    }

    private func isInMonth(_ date: Date, anchor: Date) -> Bool {
        monthResolver.contains(date, inMonthOf: anchor)
    }

    private var thisMonthTx: [Transaction] {
        store.transactions.filter { isInCurrentMonth($0.date) }
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
        let expenseTx = store.transactions.filter {
            $0.type == .expense && isInCurrentMonth($0.date)
        }
        var dict: [UUID: Int] = [:]
        for tx in expenseTx { dict[tx.categoryId, default: 0] += tx.amount }
        return dict.compactMap { (catId, sum) in
            guard let cat = store.categories.first(where: { $0.id == catId }) else { return nil }
            return CategorySlice(
                id: catId,
                name: cat.name,
                color: cat.color,
                value: sum,
                filterKey: catId.uuidString,
                symbolName: cat.symbolName
            )
        }
        .sorted { $0.value > $1.value }
    }

    private var incomeBreakdown: [CategorySlice] {
        let tx = store.transactions.filter { $0.type == .income && isInCurrentMonth($0.date) }
        var dict: [UUID: Int] = [:]
        tx.forEach { dict[$0.categoryId, default: 0] += $0.amount }
        return dict.compactMap { (id, sum) in
            guard let cat = store.categories.first(where: { $0.id == id }) else { return nil }
            return CategorySlice(
                id: id,
                name: cat.name,
                color: cat.color,
                value: sum,
                filterKey: id.uuidString,
                symbolName: cat.symbolName
            )
        }.sorted { $0.value > $1.value }
    }


    // 棒グラフ：日別支出（選択月）
    private struct DayCategoryKey: Hashable {
        let date: Date
        let categoryId: UUID
    }

    private struct SharedDayCategoryKey: Hashable {
        let date: Date
        let categoryKey: String
    }

    private var dailySeries: [DailyCategoryPoint] {
        let cal = Calendar.current
        let expenseTx = store.transactions.filter {
            $0.type == .expense && isInCurrentMonth($0.date)
        }
        var dict: [DayCategoryKey: Int] = [:]
        for tx in expenseTx {
            let day = cal.startOfDay(for: tx.date)
            let key = DayCategoryKey(date: day, categoryId: tx.categoryId)
            dict[key, default: 0] += tx.amount
        }
        return dict.keys.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.categoryId.uuidString < rhs.categoryId.uuidString
        }.map { key in
            let category = store.categories.first(where: { $0.id == key.categoryId })
            return DailyCategoryPoint(
                date: key.date,
                amount: dict[key] ?? 0,
                categoryName: category?.name ?? "未分類",
                color: category?.color ?? .gray
            )
        }
    }

    private var allThisMonthTransactions: [Transaction] {
        return store.transactions
            .filter { isInCurrentMonth($0.date) }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 共有家計簿：月次集計
    private func sharedMonthIncome(txs: [SharedTransaction]) -> Int {
        return txs
            .filter { $0.type == .income && isInCurrentMonth($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private func sharedMonthExpense(txs: [SharedTransaction]) -> Int {
        return txs
            .filter { $0.type == .expense && isInCurrentMonth($0.date) }
            .reduce(0) { $0 + $1.amount }
    }
    
    private func sharedMonthBalance(txs: [SharedTransaction]) -> Int {
        sharedMonthIncome(txs: txs) - sharedMonthExpense(txs: txs)
    }
    
    private func sharedPrevMonthExpense(allTxs: [SharedTransaction]) -> Int {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        return allTxs
            .filter { $0.type == .expense && isInMonth($0.date, anchor: prev) }
            .reduce(0) { $0 + $1.amount }
    }

    private func sharedPrevMonthIncome(allTxs: [SharedTransaction]) -> Int {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        return allTxs
            .filter { $0.type == .income && isInMonth($0.date, anchor: prev) }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - 共有家計簿：カテゴリ別円グラフ
    private func sharedExpenseBreakdown(allTxs: [SharedTransaction], categories: [SharedCategory]) -> [CategorySlice] {
        let expenseTx = allTxs.filter {
            $0.type == .expense && isInCurrentMonth($0.date)
        }

        // カテゴリ名ごとに合計
        var dict: [String: (name: String, total: Int, color: Color, symbol: String?)] = [:]
        for tx in expenseTx {
            let key = tx.categoryId?.recordName ?? tx.categoryName
            let sharedCategory = categories.first { $0.id == tx.categoryId }
            let color = Color.fromHex(sharedCategory?.colorHex ?? tx.categoryColorHex) ?? .gray
            var entry = dict[key] ?? (tx.categoryName, 0, color, sharedCategory?.icon)
            entry.total += tx.amount
            entry.symbol = entry.symbol ?? sharedCategory?.icon
            entry.color = color
            entry.name = sharedCategory?.name ?? entry.name
            dict[key] = entry
        }

        return dict.map { (key, entry) in
            CategorySlice(
                id: UUID(),
                name: entry.name,
                color: entry.color,
                value: entry.total,
                filterKey: key,
                symbolName: entry.symbol
            )
        }
        .sorted { $0.value > $1.value }
    }

    private func sharedIncomeBreakdown(allTxs: [SharedTransaction], categories: [SharedCategory]) -> [CategorySlice] {
        let incomeTx = allTxs.filter {
            $0.type == .income && isInCurrentMonth($0.date)
        }

        var dict: [String: (name: String, total: Int, color: Color, symbol: String?)] = [:]
        for tx in incomeTx {
            let key = tx.categoryId?.recordName ?? tx.categoryName
            let sharedCategory = categories.first { $0.id == tx.categoryId }
            let color = Color.fromHex(sharedCategory?.colorHex ?? tx.categoryColorHex) ?? .gray
            var entry = dict[key] ?? (tx.categoryName, 0, color, sharedCategory?.icon)
            entry.total += tx.amount
            entry.symbol = entry.symbol ?? sharedCategory?.icon
            entry.color = color
            entry.name = sharedCategory?.name ?? entry.name
            dict[key] = entry
        }

        return dict.map { (key, entry) in
            CategorySlice(
                id: UUID(),
                name: entry.name,
                color: entry.color,
                value: entry.total,
                filterKey: key,
                symbolName: entry.symbol
            )
        }
        .sorted { $0.value > $1.value }
    }
    
    // MARK: - 共有家計簿：日別棒グラフ
    private func sharedDailySeries(allTxs: [SharedTransaction], categories: [SharedCategory]) -> [DailyCategoryPoint] {
        let cal = Calendar.current
        let expenseTx = allTxs.filter {
            $0.type == .expense && isInCurrentMonth($0.date)
        }
        
        var dict: [SharedDayCategoryKey: Int] = [:]
        for tx in expenseTx {
            let day = cal.startOfDay(for: tx.date)
            let key = tx.categoryId?.recordName ?? tx.categoryName
            let categoryKey = SharedDayCategoryKey(date: day, categoryKey: key)
            dict[categoryKey, default: 0] += tx.amount
        }
        
        return dict.keys.sorted { lhs, rhs in
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.categoryKey < rhs.categoryKey
        }.map { key in
            let sharedCategory = categories.first { $0.id.recordName == key.categoryKey }
                ?? categories.first { $0.name == key.categoryKey }
            let fallbackHex = expenseTx.first { tx in
                (tx.categoryId?.recordName ?? tx.categoryName) == key.categoryKey
            }?.categoryColorHex
            let color = Color.fromHex((sharedCategory?.colorHex ?? fallbackHex)!) ?? .gray
            return DailyCategoryPoint(
                date: key.date,
                amount: dict[key] ?? 0,
                categoryName: sharedCategory?.name ?? key.categoryKey,
                color: color
            )
        }
    }
    
    private func sharedThisMonthTx(allTxs: [SharedTransaction]) -> [SharedTransaction] {
        return allTxs.filter {
            isInCurrentMonth($0.date)
        }
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
            .filter { $0.type == .expense && isInMonth($0.date, anchor: prev) }
            .reduce(0) { $0 + $1.amount }
    }

    private var prevMonthIncome: Int {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .month, value: -1, to: selectedMonth) ?? selectedMonth
        return store.transactions
            .filter { $0.type == .income && isInMonth($0.date, anchor: prev) }
            .reduce(0) { $0 + $1.amount }
    }
}

/// 1行分の表示に必要な共通データ
private struct TransactionRowContent {
    let title: String          // カテゴリ名
    let color: Color
    let symbolName: String?    // SF Symbol名（なければ頭文字を表示）
    let memo: String
    let tags: [String]
    let amount: Int
    let isIncome: Bool
    let date: Date
}

private struct TransactionRow: View {
    let row: TransactionRowContent
    
    private var displayTags: [String] {
        row.tags.map { String($0.prefix(8)) }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(row.color.opacity(0.12))
                
                if let symbol = row.symbolName {
                    Image(systemName: symbol)
                        .foregroundStyle(row.color)
                } else {
                    // SF Symbol がない場合はカテゴリ名の頭文字を表示
                    Text(String(row.title.prefix(1)))
                        .font(.caption.bold())
                        .foregroundStyle(row.color)
                }
            }
            .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(row.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    
                    if !displayTags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(displayTags.prefix(4), id: \.self) { t in
                                TagMiniChip(text: t)
                            }
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
                if !row.memo.isEmpty {
                    Text(row.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(currency(row.amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(row.isIncome ? .green : .primary)
                Text(dateStr(row.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

private struct TransactionListCard<RowID: Hashable>: View {
    let title: String
    let rows: [Row]
    let emptyMessage: String
    let onEdit: ((RowID) -> Void)?
    let onDelete: ((RowID) -> Void)?
    @EnvironmentObject var themeStore: ThemeStore
    
    struct Row: Identifiable {
        let id: RowID
        let content: TransactionRowContent
    }
    
    var body: some View {
        let isFlat = themeStore.theme.homeCardStyle == .flat
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            if rows.isEmpty {
                if isFlat {
                    VStack(spacing: 6) {
                        Text(emptyMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .padding(.horizontal, 12)
                    }
                } else {
                    Text(emptyMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .padding(.horizontal, 12)
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        )
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onEdit?(row.id)
                        } label: {
                                TransactionRow(row: row.content)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(isFlat ? Color.clear : .thinMaterial)
                                .overlay(alignment: .bottom) {
                                    if isFlat && index < rows.count - 1 {
                                        Rectangle()
                                            .fill(.secondary.opacity(0.18))
                                            .frame(height: 0.5)
                                            .padding(.horizontal, 16)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            if let onDelete {
                                Button(role: .destructive) {
                                    onDelete(row.id)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                        if !isFlat {
                            Divider().opacity(0.12)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    Group {
                        if !isFlat {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.secondary.opacity(0.12), lineWidth: 1)
                        }
                    }
                )
            }
        }
    }
}

extension TransactionListCard where RowID == UUID {
    init(
        transactions: [Transaction],
        categories: [Category],
        onEdit: @escaping (Transaction) -> Void,
        onDeleteIDs: @escaping ([UUID]) -> Void
    ) {
        self.title = "履歴"
        self.emptyMessage = "この月の履歴がまだありません。"
        
        self.rows = transactions.map { tx in
            let cat = categories.first(where: { $0.id == tx.categoryId })
            let color = cat?.color ?? .gray
            let symbol = cat?.symbolName
            
            let content = TransactionRowContent(
                title: cat?.name ?? "未分類",
                color: color,
                symbolName: symbol,
                memo: tx.memo,
                tags: tx.tags,                 // そのまま
                amount: tx.amount,
                isIncome: tx.type == .income,
                date: tx.date
            )
            
            return Row(id: tx.id, content: content)
        }
        
        self.onEdit = { id in
            if let tx = transactions.first(where: { $0.id == id }) {
                onEdit(tx)
            }
        }
        self.onDelete = { id in
            onDeleteIDs([id])
        }
    }
}

extension TransactionListCard where RowID == CKRecord.ID {
    init(
        sharedTransactions: [SharedTransaction],
        categories: [SharedCategory],
        onEdit: ((SharedTransaction) -> Void)? = nil
    ) {
        self.title = "共有家計簿の履歴"
        self.emptyMessage = "この月の共有家計簿の履歴がまだありません。"

        self.rows = sharedTransactions.sorted(by: { $0.date > $1.date }).map { tx in
            let cat: SharedCategory? = {
                if let cid = tx.categoryId {
                    return categories.first(where: { $0.id == cid })
                } else {
                    // 名前ベースでのフォールバック
                    return categories.first(where: { $0.name == tx.categoryName })
                }
            }()
            
            let hex = cat?.colorHex ?? tx.categoryColorHex
            let color = Color.fromHex(hex) ?? .gray
            let symbol = cat?.icon     // SharedCategory.icon を使う
            
            let content = TransactionRowContent(
                title: tx.categoryName,
                color: color,
                symbolName: symbol,
                memo: tx.memo ?? "",
                tags: [],                 // 共有側はタグまだないなら空
                amount: tx.amount,
                isIncome: tx.type == .income,
                date: tx.date
            )

            return Row(id: tx.id, content: content)
        }

        self.onEdit = { id in
            if let tx = sharedTransactions.first(where: { $0.id == id }) {
                onEdit?(tx)
            }
        }
        self.onDelete = nil
    }
}

// 並び替え対象のカード
private enum DashboardCard: String, CaseIterable, Identifiable {
    case header        // 月次ヘッダー（収支・支出・収入）
    case donut         // 円グラフ（支出/収入ブレイクダウン）
    case daily         // 日別推移（棒グラフ）
    case transactions  // 最近の取引リスト
    var id: String { rawValue }
}

// AppStorage で順序を保存/復元（["header","donut",...] という配列文字列で保存）
private struct CardOrderStore {
    @AppStorage("home.cardOrder") private var raw: String = ""
    func load(default order: [DashboardCard]) -> [DashboardCard] {
        guard let data = raw.data(using: .utf8),
              let ids = (try? JSONDecoder().decode([String].self, from: data)) else {
            return order
        }
        // 既知のカードだけ復元（将来カード増減しても安全）
        let map = Dictionary(uniqueKeysWithValues: DashboardCard.allCases.map { ($0.id, $0) })
        let seq = ids.compactMap { map[$0] }
        // 足りないカードは末尾に補完
        let missing = DashboardCard.allCases.filter { !seq.contains($0) }
        return seq + missing
    }
    func save(_ order: [DashboardCard]) {
        let ids = order.map(\.id)
        if let data = try? JSONEncoder().encode(ids),
           let s = String(data: data, encoding: .utf8) {
            raw = s
        }
    }
}

private struct CardDropDelegate: DropDelegate {
    let current: DashboardCard
    @Binding var items: [DashboardCard]
    @Binding var dragging: DashboardCard?
    let onCommit: () -> Void
    
    func dropEntered(info: DropInfo) {
        guard let from = dragging, from != current,
              let fromIndex = items.firstIndex(of: from),
              let toIndex   = items.firstIndex(of: current) else { return }
        
        // 順序入れ替え（アニメ付きで気持ちよく）
        withAnimation(.snappy) {
            items.move(fromOffsets: IndexSet(integer: fromIndex),
                       toOffset: (toIndex > fromIndex) ? toIndex + 1 : toIndex)
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        onCommit() // 永続化
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        // コピーではなく移動扱い
        DropProposal(operation: .move)
    }
    
    func dropExited(info: DropInfo) { }
}
