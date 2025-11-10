//
//  Views/HomeView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import Charts
import UniformTypeIdentifiers

struct HomeView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @State private var showAdd = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    
    // 既存
    @State private var selectedMonth: Date = {
        let cal = Calendar.current
        let comps = cal.dateComponents([ .year, .month ], from: Date())
        return cal.date(from: comps) ?? Date()
    }()
    @State private var editingTx: Transaction? = nil
    
    // ▼ 追加：カード順序の状態とドラッグ中のカード
    @State private var cardOrder: [DashboardCard] = CardOrderStore().load(default: [.header, .donut, .daily, .transactions])
    @State private var dragging: DashboardCard?
    
    private let dropUTIs: [UTType] = [.plainText] // onDrag のペイロード種別
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    
                    // ▼ 並び替え可能なカード群を ForEach で描画
                    ForEach(visibleCardsInOrder(), id: \.id) { card in
                        reorderableCard(card) {
                            render(card) // ← 下の render(card:) で実体ビューを返す
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
            .sheet(isPresented: $showAdd) {
                AddTransactionView(defaultCategoryId: store.categories.first?.id)
                    .environmentObject(store)
            }
            .sheet(item: $editingTx) { tx in
                EditTransactionView(transaction: tx)
                    .environmentObject(store)
            }
            .onChange(of: selectedMonth) { _, _ in
                selectedMonth = monthStart(selectedMonth)
            }
        }
        .onAppear {
            store.applyFixedExpensesForCurrentMonth()
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
            .luxCard()
            
        case .donut:
            CategoryDonutPager(
                expense: expenseBreakdown,
                expenseCurrentTotal: monthExpense,
                expensePreviousTotal: prevMonthExpense,
                income: incomeBreakdown,
                incomeCurrentTotal: monthIncome,
                incomePreviousTotal: prevMonthIncome
            )
            .luxCard()
            
        case .daily:
            DailyBarChart(series: dailySeries)
                .luxCard()
            
        case .transactions:
            TransactionListCard(
                transactions: allThisMonthTransactions,
                categories: store.categories,
                onEdit: { tx in editingTx = tx },
                onDeleteIDs: { ids in store.deleteTransactions(with: ids) }
            )
            .luxCard()
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
    
    private var displayTags: [String] {
        tx.tags.map { String($0.prefix(8)) }
    }
    
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
                HStack(spacing: 8) {
                    Text(category.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    
                    // タグチップ（最大4個表示）
                    if !displayTags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(displayTags.prefix(4), id: \.self) { t in
                                TagMiniChip(text: t)
                            }
                        }
                    }
                    
                    Spacer(minLength: 0)
                }
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
