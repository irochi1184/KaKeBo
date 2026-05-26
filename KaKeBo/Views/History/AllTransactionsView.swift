//
//  Views/History/AllTransactionsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/05.
//

import SwiftUI
import CloudKit
import Charts

struct AllTransactionsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var purchase: PurchaseManager
    @Environment(\.colorScheme) private var scheme
    
    // 検索テキスト
    @State private var searchText: String = ""

    // 絞り込み条件
    @State private var selectedType: TransactionType? = nil
    @State private var selectedCategoryIDs: Set<UUID> = []
    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil
    @State private var minAmount: Int? = nil
    @State private var maxAmount: Int? = nil
    @State private var selectedTags: Set<String> = []
    @State private var editingTx: Transaction? = nil
    @State private var showFilter = false
    @State private var selectedSort: TransactionSortOption = .dateDesc
    @State private var favoriteFilters: [FavoriteFilter] = []

    // 共有用の絞り込み状態
    @State private var sharedSelectedType: SharedTransactionType? = nil
    @State private var sharedSelectedCategoryIDs: Set<CKRecord.ID> = []
    @State private var sharedDateFrom: Date? = nil
    @State private var sharedDateTo: Date? = nil
    @State private var sharedMinAmount: Int? = nil
    @State private var sharedMaxAmount: Int? = nil
    @State private var sharedSelectedTags: Set<String> = []
    @State private var editingSharedTx: SharedTransaction? = nil
    @State private var sharedSelectedSort: TransactionSortOption = .dateDesc

    @State private var currentPage: Int = 0
    @State private var showChartSheet = false
    @State private var showChartLimitAlert = false

    @AppStorage("historyFilterChartUsageMonth") private var chartUsageMonth: String = ""
    @AppStorage("historyFilterChartUsageCount") private var chartUsageCount: Int = 0

    private let itemsPerPage = 100
    
    // タグの正規化（検索・比較用）：8文字・lowercased
    private func normTag(_ raw: String) -> String {
        String(raw.prefix(8)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    // 取引の正規化済みタグ配列
    private func normTags(_ tags: [String]) -> [String] {
        tags.map { normTag($0) }
    }
    // 全取引から重複を除いた全タグ（表示用は原文8文字切り詰め。内部キーは lowercased 8文字）
    private var allTagsForFilter: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let tagSource: [String]
        if ledgerContext.mode == .shared,
           ledgerContext.currentSharedLedger(from: sharedLedgerStore) != nil {
            tagSource = []
        } else {
            tagSource = store.transactions.flatMap { $0.tags }
        }

        for t in tagSource {
            let key = normTag(t)
            if !key.isEmpty, !seen.contains(key) {
                seen.insert(key)
                result.append(String(t.prefix(8)))
            }
        }
        // 見やすさのためアルファベット順（日本語もUnicode順）
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    
    var body: some View {
        let accent = themeStore.theme.accentColor(for: scheme)
        NavigationStack {
            VStack(spacing: 0) {
                // 検索バー + フィルタを横並び
                HStack(alignment: .center, spacing: 12) {
                    LedgerModePicker(style: .circleIcon)
                        .tint(accent)
                        .padding(.leading, 4)

                    SearchHeader(
                        text: $searchText,
                        isFiltering: isFiltering,
                        accent: accent,
                        favorites: favoriteFilters,
                        categories: store.categories,
                        onTapFilter: { showFilter = true },
                        onClear: resetFilters,
                        onApplyFavorite: { applyFavorite($0) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal)
                .padding(.bottom, 6)

                // サマリー
                SummaryBar(
                    totalIncome: filteredIncomeTotal,
                    totalExpense: filteredExpenseTotal,
                    count: displayed.count,
                    accent: accent
                )
                .padding(.horizontal)
                .padding(.bottom, 6)

                if isFiltering, !displayed.isEmpty {
                    filterChartAction
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                contentList
            }
            .background(themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showFilter, onDismiss: {
            favoriteFilters = FavoriteFilter.loadAll()
        }) {
            if ledgerContext.mode == .shared,
               let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore) {
                SharedFilterSheet(
                    allCategories: sharedLedgerStore.categoriesByLedger[ledger.id] ?? [],
                    selectedType: $sharedSelectedType,
                    selectedCategoryIDs: $sharedSelectedCategoryIDs,
                    dateFrom: $sharedDateFrom,
                    dateTo: $sharedDateTo,
                    minAmount: $sharedMinAmount,
                    maxAmount: $sharedMaxAmount,
                    allTags: allTagsForFilter,
                    selectedTags: $sharedSelectedTags,
                    selectedSort: $sharedSelectedSort
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            } else {
                FilterSheet(
                    allCategories: store.categories,
                    selectedType: $selectedType,
                    selectedCategoryIDs: $selectedCategoryIDs,
                    dateFrom: $dateFrom,
                    dateTo: $dateTo,
                    minAmount: $minAmount,
                    maxAmount: $maxAmount,
                    selectedSort: $selectedSort,
                    allTags: allTagsForFilter,
                    selectedTags: $selectedTags
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
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
        .task(id: ledgerContext.selectedSharedLedgerId) { await reloadSharedLedgerDataIfNeeded() }
        .onAppear {
            syncChartUsageMonth()
            favoriteFilters = FavoriteFilter.loadAll()
        }
        .onChange(of: displayed.count) { _, _ in
            if currentPage >= totalPages {
                currentPage = max(0, totalPages - 1)
            }
        }
        .onChange(of: filterSignature) { _, _ in
            currentPage = 0
        }
        .alert("グラフ表示の上限に達しました", isPresented: $showChartLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("無料プランではフィルター結果のグラフ表示は月に3回までご利用いただけます。プレミアムプランなら回数制限なくご利用いただけます。")
        }
        .sheet(isPresented: $showChartSheet) {
            FilteredChartsSheet(
                transactions: displayed,
                background: themeStore.theme.backgroundColor(for: scheme)
            )
        }
    }
}

private extension AllTransactionsView {
    var filterChartAction: some View {
        let remaining = max(0, 3 - chartUsageCount)
        return Button {
            requestShowCharts()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chart.pie.fill")
                Text("フィルター結果をグラフ表示")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !purchase.isPremiumActive {
                    Text("残り\(remaining)回")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("無制限")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(themeStore.theme.accentColor(for: scheme).opacity(0.12))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    var contentList: some View {
        VStack(spacing: 0) {
            List {
                ForEach(pagedDisplayed) { item in
                    Button {
                        if let tx = item.personal {
                            editingTx = tx
                        } else if let tx = item.shared {
                            editingSharedTx = tx
                        }
                    } label: {
                        HistoryRow(content: item)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(themeStore.theme.backgroundColor(for: scheme))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            if shouldShowPagination {
                paginationRow
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(themeStore.theme.backgroundColor(for: scheme))
            }
        }
        .background(themeStore.theme.backgroundColor(for: scheme))
    }

    private var currentSharedLedger: SharedLedger? {
        ledgerContext.currentSharedLedger(from: sharedLedgerStore)
    }

    var displayed: [DisplayTransaction] {
        switch ledgerContext.mode {
        case .personal:
            return personalDisplay
        case .shared:
            return sharedDisplay
        }
    }

    private var personalDisplay: [DisplayTransaction] {
        filteredPersonal.map { tx in
            let cat = store.categories.first(where: { $0.id == tx.categoryId })
            let color = cat?.color ?? .gray
            let symbol = cat?.symbolName ?? "questionmark"

            return DisplayTransaction(
                id: tx.id.uuidString,
                title: cat?.name ?? "未分類",
                color: color,
                symbolName: symbol,
                memo: tx.memo,
                tags: tx.tags,
                amount: tx.amount,
                isIncome: tx.type == .income,
                date: tx.date,
                personal: tx,
                shared: nil
            )
        }
    }

    private var sharedDisplay: [DisplayTransaction] {
        guard let ledger = currentSharedLedger else { return [] }
        let cats = sharedLedgerStore.categoriesByLedger[ledger.id] ?? []

        return filteredShared.map { tx in
            let cat: SharedCategory? = {
                if let cid = tx.categoryId {
                    return cats.first(where: { $0.id == cid })
                }
                return cats.first(where: { $0.name == tx.categoryName })
            }()

            let hex = cat?.colorHex ?? tx.categoryColorHex
            let color = Color.fromHex(hex) ?? .gray
            let symbol = cat?.icon ?? "tag.fill"

            return DisplayTransaction(
                id: tx.id.recordName,
                title: tx.categoryName,
                color: color,
                symbolName: symbol,
                memo: (tx.memo ?? ""),
                tags: [],
                amount: tx.amount,
                isIncome: tx.type == .income,
                date: tx.date,
                personal: nil,
                shared: tx
            )
        }
    }

    func reloadSharedLedgerDataIfNeeded() async {
        guard ledgerContext.isShared,
              let ledger = currentSharedLedger else { return }

        await sharedLedgerStore.reloadCategories(for: ledger)
        await sharedLedgerStore.reloadTransactions(for: ledger)
    }

    var totalPages: Int {
        max(1, Int(ceil(Double(displayed.count) / Double(itemsPerPage))))
    }

    var shouldShowPagination: Bool {
        displayed.count > itemsPerPage
    }

    var pagedDisplayed: [DisplayTransaction] {
        guard shouldShowPagination else { return displayed }
        let start = currentPage * itemsPerPage
        let end = min(start + itemsPerPage, displayed.count)
        if start >= displayed.count { return [] }
        return Array(displayed[start..<end])
    }

    var paginationRow: some View {
        HStack(spacing: 12) {
            Button {
                currentPage = max(0, currentPage - 1)
            } label: {
                Label("前へ", systemImage: "chevron.left")
            }
            .disabled(currentPage == 0)

            Spacer()

            Text("\(currentPage + 1) / \(totalPages)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                currentPage = min(totalPages - 1, currentPage + 1)
            } label: {
                Label("次へ", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(currentPage >= totalPages - 1)
        }
    }

    var filterSignature: String {
        switch ledgerContext.mode {
        case .personal:
            return personalFilterSignature()
        case .shared:
            return sharedFilterSignature()
        }
    }

    func personalFilterSignature() -> String {
        let categories = selectedCategoryIDs.map { $0.uuidString }.sorted().joined(separator: ",")
        let tags = selectedTags.sorted().joined(separator: ",")
        let from = dateFrom?.description ?? "nil"
        let to = dateTo?.description ?? "nil"
        let min = minAmount.map(String.init) ?? "nil"
        let max = maxAmount.map(String.init) ?? "nil"
        let parts = [
            searchText.lowercased(),
            selectedType?.rawValue ?? "all",
            categories,
            from,
            to,
            min,
            max,
            tags,
            selectedSort.rawValue
        ]
        return parts.joined(separator: "|")
    }

    func sharedFilterSignature() -> String {
        let categories = sharedSelectedCategoryIDs.map(\.recordName).sorted().joined(separator: ",")
        let tags = sharedSelectedTags.sorted().joined(separator: ",")
        let from = sharedDateFrom?.description ?? "nil"
        let to = sharedDateTo?.description ?? "nil"
        let min = sharedMinAmount.map(String.init) ?? "nil"
        let max = sharedMaxAmount.map(String.init) ?? "nil"
        let ledgerId = ledgerContext.selectedSharedLedgerId?.recordName ?? "nil"
        let parts = [
            searchText.lowercased(),
            sharedSelectedType?.rawValue ?? "all",
            categories,
            from,
            to,
            min,
            max,
            tags,
            sharedSelectedSort.rawValue,
            ledgerId
        ]
        return parts.joined(separator: "|")
    }

    func requestShowCharts() {
        syncChartUsageMonth()
        if purchase.isPremiumActive {
            showChartSheet = true
            return
        }
        if chartUsageCount >= 3 {
            showChartLimitAlert = true
            return
        }
        chartUsageCount += 1
        showChartSheet = true
    }

    func syncChartUsageMonth() {
        let current = currentMonthKey()
        if chartUsageMonth != current {
            chartUsageMonth = current
            chartUsageCount = 0
        }
    }

    func currentMonthKey() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: Date())
    }
}

private enum TransactionSortOption: String, CaseIterable, Identifiable {
    case dateDesc
    case categoryAsc
    case amountDesc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateDesc:
            return "日付順"
        case .categoryAsc:
            return "カテゴリ順"
        case .amountDesc:
            return "金額の大きい順"
        }
    }
}

// MARK: - 検索＋フィルタ ヘッダ

private struct SearchHeader: View {
    @Binding var text: String
    let isFiltering: Bool
    let accent: Color
    let favorites: [FavoriteFilter]
    let categories: [Category]
    let onTapFilter: () -> Void
    let onClear: () -> Void
    let onApplyFavorite: (FavoriteFilter) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            // 擬似検索フィールド
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("メモ・カテゴリ・タグを検索", text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.08) : .white)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 8, y: 2)
            )

            // お気に入りメニュー（保存済みがある場合のみ表示）
            if !favorites.isEmpty {
                Menu {
                    ForEach(favorites) { fav in
                        Button {
                            onApplyFavorite(fav)
                        } label: {
                            Label(fav.name, systemImage: "star.fill")
                        }
                    }
                } label: {
                    Image(systemName: "star.fill")
                        .imageScale(.medium)
                        .foregroundStyle(.orange)
                        .frame(width: 36, height: 36)
                        .background(
                            Circle()
                                .fill(Color.orange.opacity(0.12))
                        )
                }
            }

            // フィルタボタン
            Button(action: onTapFilter) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .imageScale(.large)
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(accent.opacity(0.12))
                            .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.8))
                    )
            }
            .buttonStyle(.plain)

            // クリア
            if isFiltering {
                Button("クリア", action: onClear)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}

// MARK: - フィルタ適用

private extension AllTransactionsView {
    var filteredPersonal: [Transaction] {
        var items = store.transactions

        func categoryName(for tx: Transaction) -> String {
            store.categories.first(where: { $0.id == tx.categoryId })?.name ?? "未分類"
        }

        // キーワード検索：メモ / カテゴリ名 / タグ
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter { tx in
                let memoHit = tx.memo.lowercased().contains(q)
                let catName = store.categories.first(where: { $0.id == tx.categoryId })?.name.lowercased() ?? ""
                let tagHit  = normTags(tx.tags).contains { $0.contains(q) }
                return memoHit || catName.contains(q) || tagHit
            }
        }
        // 種別
        if let kind = selectedType {
            items = items.filter { $0.type == kind }
        }
        // カテゴリ
        if !selectedCategoryIDs.isEmpty {
            items = items.filter { selectedCategoryIDs.contains($0.categoryId) }
        }
        // タグフィルター（選択タグのいずれかを含む取引だけに絞る）
        if !selectedTags.isEmpty {
            items = items.filter { tx in
                let txTags = Set(normTags(tx.tags))
                return !selectedTags.isDisjoint(with: txTags)
            }
        }
        // 期間
        if let from = dateFrom {
            items = items.filter { $0.date >= Calendar.current.startOfDay(for: from) }
        }
        if let to = dateTo {
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: to) ?? to
            items = items.filter { $0.date <= endOfDay }
        }
        // 金額
        if let lo = minAmount {
            items = items.filter { $0.amount >= lo }
        }
        if let hi = maxAmount {
            items = items.filter { $0.amount <= hi }
        }
        return items.sorted { lhs, rhs in
            switch selectedSort {
            case .dateDesc:
                return lhs.date > rhs.date
            case .categoryAsc:
                let lName = categoryName(for: lhs)
                let rName = categoryName(for: rhs)
                if lName != rName {
                    return lName.localizedStandardCompare(rName) == .orderedAscending
                }
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.amount > rhs.amount
            case .amountDesc:
                if lhs.amount != rhs.amount {
                    return lhs.amount > rhs.amount
                }
                return lhs.date > rhs.date
            }
        }
    }

    var filteredShared: [SharedTransaction] {
        guard let ledger = currentSharedLedger else { return [] }
        var items = sharedLedgerStore.transactionsByLedger[ledger.id] ?? []
        let categories = sharedLedgerStore.categoriesByLedger[ledger.id] ?? []

        func categoryName(for tx: SharedTransaction) -> String {
            if let cid = tx.categoryId,
               let cat = categories.first(where: { $0.id == cid }) {
                return cat.name
            }
            if let fallback = categories.first(where: { $0.name == tx.categoryName }) {
                return fallback.name
            }
            return tx.categoryName
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter { tx in
                let memoHit = (tx.memo ?? "").lowercased().contains(q)
                let catName = categories.first(where: { $0.id == tx.categoryId })?.name.lowercased() ?? tx.categoryName.lowercased()
                return memoHit || catName.contains(q)
            }
        }
        if let kind = sharedSelectedType {
            items = items.filter { $0.type == kind }
        }
        if !sharedSelectedCategoryIDs.isEmpty {
            items = items.filter { tx in
                if let cid = tx.categoryId, sharedSelectedCategoryIDs.contains(cid) { return true }
                if let fallback = categories.first(where: { $0.name == tx.categoryName }) {
                    return sharedSelectedCategoryIDs.contains(fallback.id)
                }
                return false
            }
        }
        if !sharedSelectedTags.isEmpty {
            items = items.filter { tx in
                let txTags = Set(normTags([]))
                return !sharedSelectedTags.isDisjoint(with: txTags)
            }
        }
        if let from = sharedDateFrom {
            items = items.filter { $0.date >= Calendar.current.startOfDay(for: from) }
        }
        if let to = sharedDateTo {
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: to) ?? to
            items = items.filter { $0.date <= endOfDay }
        }
        if let lo = sharedMinAmount {
            items = items.filter { $0.amount >= lo }
        }
        if let hi = sharedMaxAmount {
            items = items.filter { $0.amount <= hi }
        }
        return items.sorted { lhs, rhs in
            switch sharedSelectedSort {
            case .dateDesc:
                return lhs.date > rhs.date
            case .categoryAsc:
                let lName = categoryName(for: lhs)
                let rName = categoryName(for: rhs)
                if lName != rName {
                    return lName.localizedStandardCompare(rName) == .orderedAscending
                }
                if lhs.date != rhs.date {
                    return lhs.date > rhs.date
                }
                return lhs.amount > rhs.amount
            case .amountDesc:
                if lhs.amount != rhs.amount {
                    return lhs.amount > rhs.amount
                }
                return lhs.date > rhs.date
            }
        }
    }

    var filteredIncomeTotal: Int { displayed.filter { $0.isIncome }.reduce(0) { $0 + $1.amount } }
    var filteredExpenseTotal: Int { displayed.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount } }

    var isFiltering: Bool {
        if !searchText.isEmpty { return true }
        switch ledgerContext.mode {
        case .personal:
            return personalFilterActive
        case .shared:
            return sharedFilterActive
        }
    }

    var personalFilterActive: Bool {
        if selectedType != nil { return true }
        if !selectedCategoryIDs.isEmpty { return true }
        if dateFrom != nil || dateTo != nil { return true }
        if minAmount != nil || maxAmount != nil { return true }
        if !selectedTags.isEmpty { return true }
        return false
    }

    var sharedFilterActive: Bool {
        if sharedSelectedType != nil { return true }
        if !sharedSelectedCategoryIDs.isEmpty { return true }
        if sharedDateFrom != nil || sharedDateTo != nil { return true }
        if sharedMinAmount != nil || sharedMaxAmount != nil { return true }
        if !sharedSelectedTags.isEmpty { return true }
        return false
    }

    func applyFavorite(_ fav: FavoriteFilter) {
        selectedType = fav.transactionTypeRaw.flatMap { TransactionType(rawValue: $0) }
        selectedCategoryIDs = Set(fav.categoryIDs)
        selectedTags = Set(fav.tags)
        minAmount = fav.minAmount
        maxAmount = fav.maxAmount
        selectedSort = TransactionSortOption(rawValue: fav.sortRaw) ?? .dateDesc
        dateFrom = nil
        dateTo = nil
    }

    func resetFilters() {
        searchText = ""
        selectedType = nil
        selectedCategoryIDs = []
        dateFrom = nil
        dateTo = nil
        minAmount = nil
        maxAmount = nil
        selectedTags.removeAll()
        selectedSort = .dateDesc

        sharedSelectedType = nil
        sharedSelectedCategoryIDs = []
        sharedDateFrom = nil
        sharedDateTo = nil
        sharedMinAmount = nil
        sharedMaxAmount = nil
        sharedSelectedTags.removeAll()
        sharedSelectedSort = .dateDesc
    }
}

// MARK: - サマリー

private struct SummaryBar: View {
    @Environment(\.appIncomeColor) private var incomeColor
    @Environment(\.appExpenseColor) private var expenseColor
    let totalIncome: Int
    let totalExpense: Int
    let count: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            StatPill(title: "収入", value: totalIncome, color: incomeColor)
            StatPill(title: "支出", value: totalExpense, color: expenseColor)
            Spacer()
            Text("\(count)件")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private struct StatPill: View {
        let title: String
        let value: Int
        let color: Color

        var body: some View {
            HStack(spacing: 6) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(currency(value))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                Capsule().fill(color.opacity(0.10))
                    .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.8))
            )
        }

        private func currency(_ n: Int) -> String {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
        }
    }
}

private struct DisplayTransaction: Identifiable {
    let id: String
    let title: String
    let color: Color
    let symbolName: String?
    let memo: String
    let tags: [String]
    let amount: Int
    let isIncome: Bool
    let date: Date
    let personal: Transaction?
    let shared: SharedTransaction?
}

// MARK: - 行表示

private struct HistoryRow: View {
    let content: DisplayTransaction
    @Environment(\.appIncomeColor) private var incomeColor
    @Environment(\.appExpenseColor) private var expenseColor

    private var displayTags: [String] {
        content.tags.map { String($0.prefix(8)) }
    }

    var body: some View {
        HStack(spacing: 12) {
            // 左：カテゴリアイコン
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(content.color.opacity(0.12))
                Image(systemName: content.symbolName ?? "tag.fill")
                    .foregroundStyle(content.color)
            }
            .frame(width: 36, height: 36)

            // 中央：カテゴリ名 + タグ（横並び）
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(content.title)
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

                let memo = content.memo.trimmingCharacters(in: .whitespacesAndNewlines)
                if !memo.isEmpty {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // 右：金額と日付
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountStr())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(content.isIncome ? incomeColor : expenseColor)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(dateStr(content.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func amountStr() -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let sign = content.isIncome ? "+" : "-"
        return sign + "¥" + (f.string(from: content.amount as NSNumber) ?? "\(content.amount)")
    }
    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy/MM/dd(E)"
        return f.string(from: d)
    }
}


// MARK: - フィルタシート

private struct FilterSheet: View {
    let allCategories: [Category]
    @Binding var selectedType: TransactionType?
    @Binding var selectedCategoryIDs: Set<UUID>
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var minAmount: Int?
    @Binding var maxAmount: Int?
    @Binding var selectedSort: TransactionSortOption

    // ★ タグ
    let allTags: [String]                    // 表示用（最大8文字）
    @Binding var selectedTags: Set<String>   // 正規化キー lowercased 8文字

    @Environment(\.dismiss) private var dismiss

    @State private var favorites: [FavoriteFilter] = []
    @State private var showSaveAlert = false
    @State private var saveName = ""
    @State private var showDeleteConfirm: FavoriteFilter? = nil

    // ★ 表示→内部キー変換
    private func key(_ display: String) -> String {
        String(display.prefix(8)).lowercased()
    }

    // 現在の条件をお気に入りとして保存
    private func buildFavorite(name: String) -> FavoriteFilter {
        FavoriteFilter(
            name: name,
            transactionTypeRaw: selectedType?.rawValue,
            categoryIDs: Array(selectedCategoryIDs),
            tags: Array(selectedTags),
            minAmount: minAmount,
            maxAmount: maxAmount,
            sortRaw: selectedSort.rawValue
        )
    }

    // お気に入りを適用
    private func applyFavorite(_ fav: FavoriteFilter) {
        selectedType = fav.transactionTypeRaw.flatMap { TransactionType(rawValue: $0) }
        selectedCategoryIDs = Set(fav.categoryIDs)
        selectedTags = Set(fav.tags)
        minAmount = fav.minAmount
        maxAmount = fav.maxAmount
        selectedSort = TransactionSortOption(rawValue: fav.sortRaw) ?? .dateDesc
        // 期間はリセット（お気に入りに含めない）
        dateFrom = nil
        dateTo = nil
    }

    // 現在フィルター条件が設定されているか
    private var hasAnyCondition: Bool {
        selectedType != nil ||
        !selectedCategoryIDs.isEmpty ||
        !selectedTags.isEmpty ||
        minAmount != nil ||
        maxAmount != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                // お気に入りセクション
                if !favorites.isEmpty {
                    Section {
                        ForEach(favorites) { fav in
                            Button {
                                applyFavorite(fav)
                                dismiss()
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(fav.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Text(fav.summaryText(categories: allCategories))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    favorites.removeAll { $0.id == fav.id }
                                    FavoriteFilter.saveAll(favorites)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        Text("保存した条件")
                    }
                }

                Section("並び替え") {
                    Picker("並び替え", selection: $selectedSort) {
                        ForEach(TransactionSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("種別") {
                    Picker("種別", selection: $selectedType) {
                        Text("すべて").tag(TransactionType?.none)
                        Text("収入のみ").tag(TransactionType?.some(.income))
                        Text("支出のみ").tag(TransactionType?.some(.expense))
                    }
                    .pickerStyle(.segmented)
                }
                
                Section("カテゴリ") {
                    if allCategories.isEmpty {
                        Text("カテゴリがありません").foregroundStyle(.secondary)
                    } else {
                        ForEach(allCategories) { cat in
                            HStack {
                                Image(systemName: selectedCategoryIDs.contains(cat.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(cat.color)
                                Text(cat.name)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedCategoryIDs.contains(cat.id) {
                                    selectedCategoryIDs.remove(cat.id)
                                } else {
                                    selectedCategoryIDs.insert(cat.id)
                                }
                            }
                        }
                        if !selectedCategoryIDs.isEmpty {
                            Button("選択をクリア", role: .destructive) { selectedCategoryIDs.removeAll() }
                                .font(.footnote)
                        }
                    }
                }
                
                // タグ
                Section("タグ") {
                    if allTags.isEmpty {
                        Text("タグがありません").foregroundStyle(.secondary)
                    } else {
                        // 自動折返しで均一スペースのチップ群（FlowLayout を使ってもOK）
                        let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                            ForEach(allTags, id: \.self) { t in
                                let k = key(t)
                                let on = selectedTags.contains(k)
                                Button {
                                    if on { selectedTags.remove(k) } else { selectedTags.insert(k) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                                            .imageScale(.small)
                                        Text(String(t.prefix(8)))
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(
                                        Capsule().fill(on ? Color.accentColor.opacity(0.18)
                                                       : Color.secondary.opacity(0.10))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !selectedTags.isEmpty {
                            Button("タグをクリア", role: .destructive) { selectedTags.removeAll() }
                                .font(.footnote)
                        }
                    }
                }
                
                Section("期間") {
                    let fromBinding = Binding<Date>(
                        get: { dateFrom ?? Date() },
                        set: { newVal in dateFrom = newVal }
                    )
                    let toBinding = Binding<Date>(
                        get: { dateTo ?? Date() },
                        set: { newVal in dateTo = newVal }
                    )
                    DatePicker("開始日", selection: fromBinding, displayedComponents: .date)
                    DatePicker("終了日", selection: toBinding, displayedComponents: .date)
                    if dateFrom != nil || dateTo != nil {
                        Button("期間をクリア") { dateFrom = nil; dateTo = nil }
                            .font(.footnote)
                    }
                }
                
                Section("金額範囲") {
                    AmountField(title: "最小", value: $minAmount)
                    AmountField(title: "最大", value: $maxAmount)
                    if minAmount != nil || maxAmount != nil {
                        Button("金額をクリア") { minAmount = nil; maxAmount = nil }
                            .font(.footnote)
                    }
                }
            }
                // 条件保存ボタン
                if hasAnyCondition {
                    Section {
                        Button {
                            saveName = ""
                            showSaveAlert = true
                        } label: {
                            Label("現在の条件を保存", systemImage: "star.fill")
                        }
                    }
                }
            }
            .navigationTitle("絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
            .onAppear { favorites = FavoriteFilter.loadAll() }
            .alert("条件の保存", isPresented: $showSaveAlert) {
                TextField("名前を入力", text: $saveName)
                Button("保存") {
                    let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    favorites.append(buildFavorite(name: name))
                    FavoriteFilter.saveAll(favorites)
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この絞り込み条件に名前をつけて保存します")
            }
        }
    }
}

private struct SharedFilterSheet: View {
    let allCategories: [SharedCategory]
    @Binding var selectedType: SharedTransactionType?
    @Binding var selectedCategoryIDs: Set<CKRecord.ID>
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var minAmount: Int?
    @Binding var maxAmount: Int?
    @Binding var selectedSort: TransactionSortOption

    let allTags: [String]
    @Binding var selectedTags: Set<String>

    @Environment(\.dismiss) private var dismiss

    private func key(_ display: String) -> String {
        String(display.prefix(8)).lowercased()
    }

    private func color(for cat: SharedCategory) -> Color {
        Color.fromHex(cat.colorHex) ?? .accentColor
    }
    
    init(
        allCategories: [SharedCategory],
        selectedType: Binding<SharedTransactionType?>,
        selectedCategoryIDs: Binding<Set<CKRecord.ID>>,
        dateFrom: Binding<Date?>,
        dateTo: Binding<Date?>,
        minAmount: Binding<Int?>,
        maxAmount: Binding<Int?>,
        allTags: [String],
        selectedTags: Binding<Set<String>>,
        selectedSort: Binding<TransactionSortOption>
    ) {
        self.allCategories = allCategories
        self._selectedType = selectedType
        self._selectedCategoryIDs = selectedCategoryIDs
        self._dateFrom = dateFrom
        self._dateTo = dateTo
        self._minAmount = minAmount
        self._maxAmount = maxAmount
        self.allTags = allTags
        self._selectedTags = selectedTags
        self._selectedSort = selectedSort
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("並び替え") {
                    Picker("並び替え", selection: $selectedSort) {
                        ForEach(TransactionSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("種別") {
                    Picker("種別", selection: $selectedType) {
                        Text("すべて").tag(SharedTransactionType?.none)
                        Text("収入のみ").tag(SharedTransactionType?.some(.income))
                        Text("支出のみ").tag(SharedTransactionType?.some(.expense))
                    }
                    .pickerStyle(.segmented)
                }

                Section("カテゴリ") {
                    if allCategories.isEmpty {
                        Text("カテゴリがありません").foregroundStyle(.secondary)
                    } else {
                        ForEach(allCategories) { cat in
                            let col = color(for: cat)
                            HStack {
                                Image(systemName: selectedCategoryIDs.contains(cat.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(col)
                                Text(cat.name)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if selectedCategoryIDs.contains(cat.id) {
                                    selectedCategoryIDs.remove(cat.id)
                                } else {
                                    selectedCategoryIDs.insert(cat.id)
                                }
                            }
                        }
                        if !selectedCategoryIDs.isEmpty {
                            Button("選択をクリア", role: .destructive) { selectedCategoryIDs.removeAll() }
                                .font(.footnote)
                        }
                    }
                }

                Section("タグ") {
                    if allTags.isEmpty {
                        Text("タグがありません").foregroundStyle(.secondary)
                    } else {
                        let columns = [GridItem(.adaptive(minimum: 80), spacing: 8)]
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                            ForEach(allTags, id: \.self) { t in
                                let k = key(t)
                                let on = selectedTags.contains(k)
                                Button {
                                    if on { selectedTags.remove(k) } else { selectedTags.insert(k) }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: on ? "checkmark.circle.fill" : "plus.circle")
                                            .imageScale(.small)
                                        Text(String(t.prefix(8)))
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(
                                        Capsule().fill(on ? Color.accentColor.opacity(0.18)
                                                       : Color.secondary.opacity(0.10))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !selectedTags.isEmpty {
                            Button("タグをクリア", role: .destructive) { selectedTags.removeAll() }
                                .font(.footnote)
                        }
                    }
                }

                Section("期間") {
                    let fromBinding = Binding<Date>(
                        get: { dateFrom ?? Date() },
                        set: { newVal in dateFrom = newVal }
                    )
                    let toBinding = Binding<Date>(
                        get: { dateTo ?? Date() },
                        set: { newVal in dateTo = newVal }
                    )
                    DatePicker("開始日", selection: fromBinding, displayedComponents: .date)
                    DatePicker("終了日", selection: toBinding, displayedComponents: .date)
                    if dateFrom != nil || dateTo != nil {
                        Button("期間をクリア") { dateFrom = nil; dateTo = nil }
                            .font(.footnote)
                    }
                }

                Section("金額範囲") {
                    AmountField(title: "最小", value: $minAmount)
                    AmountField(title: "最大", value: $maxAmount)
                    if minAmount != nil || maxAmount != nil {
                        Button("金額をクリア") { minAmount = nil; maxAmount = nil }
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("絞り込み")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                }
            }
        }
    }
}

private struct AmountField: View {
    let title: String
    @Binding var value: Int?
    @State private var text: String = ""
    
    var body: some View {
        HStack {
            Text(title)
            TextField("例: 10000", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
        .onAppear {
            if text.isEmpty, let v = value { text = String(v) }
        }
        .onChange(of: text) { _, newVal in
            let digits = newVal.filter { $0.isNumber }
            if digits != newVal { text = digits }
            value = digits.isEmpty ? nil : Int(digits)
        }
    }
}

private struct FilteredChartsSheet: View {
    let transactions: [DisplayTransaction]
    let background: Color

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if transactions.isEmpty {
                        Text("表示できる取引がありません。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        if !expenseSlices.isEmpty {
                            CategoryDonutChart(
                                breakdown: expenseSlices,
                                currentTotal: expenseTotal,
                                previousTotal: 0,
                                isExpense: true
                            )
                            .luxCard()
                        }

                        if !incomeSlices.isEmpty {
                            CategoryDonutChart(
                                breakdown: incomeSlices,
                                currentTotal: incomeTotal,
                                previousTotal: 0,
                                isExpense: false
                            )
                            .luxCard()
                        }

                        FilteredBarChart(series: dailySeries)
                    }
                }
                .padding()
            }
            .background(background.ignoresSafeArea())
            .navigationTitle("フィルター結果のグラフ")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                ReviewRequestManager.shared.recordReportScreenViewed()
                ReviewRequestManager.shared.scheduleReviewRequestIfEligible()
            }
        }
    }

    private var expenseTotal: Int {
        transactions.filter { !$0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private var incomeTotal: Int {
        transactions.filter { $0.isIncome }.reduce(0) { $0 + $1.amount }
    }

    private var expenseSlices: [CategorySlice] {
        makeSlices(isIncome: false)
    }

    private var incomeSlices: [CategorySlice] {
        makeSlices(isIncome: true)
    }

    private func makeSlices(isIncome: Bool) -> [CategorySlice] {
        var dict: [String: (color: Color, amount: Int, symbol: String?)] = [:]
        for tx in transactions where tx.isIncome == isIncome {
            let key = tx.title
            var entry = dict[key] ?? (tx.color, 0, tx.symbolName)
            entry.amount += tx.amount
            dict[key] = entry
        }
        return dict.map { key, value in
            CategorySlice(
                id: UUID(),
                name: key,
                color: value.color,
                value: value.amount,
                symbolName: value.symbol
            )
        }
        .sorted { $0.value > $1.value }
    }

    private var dailySeries: [FilteredDailyCategoryPoint] {
        var dict: [DailyCategoryKey: FilteredDailyCategoryPoint] = [:]
        let calendar = Calendar.current
        let signed = usesSignedAmount
        for tx in transactions {
            let day = calendar.startOfDay(for: tx.date)
            let amount = signed ? (tx.isIncome ? tx.amount : -tx.amount) : tx.amount
            let key = DailyCategoryKey(
                date: day,
                category: tx.title,
                isIncome: tx.isIncome
            )
            if var point = dict[key] {
                point.amount += amount
                dict[key] = point
            } else {
                dict[key] = FilteredDailyCategoryPoint(
                    date: day,
                    amount: amount,
                    category: tx.title,
                    color: tx.color,
                    isIncome: tx.isIncome
                )
            }
        }
        return dict
            .map(\.value)
            .sorted {
                if $0.date != $1.date { return $0.date < $1.date }
                if $0.isIncome != $1.isIncome { return $0.isIncome && !$1.isIncome }
                return $0.category < $1.category
            }
    }

    private var hasIncome: Bool {
        transactions.contains { $0.isIncome }
    }

    private var hasExpense: Bool {
        transactions.contains { !$0.isIncome }
    }

    private var usesSignedAmount: Bool {
        hasIncome && hasExpense
    }
}

private struct DailyCategoryKey: Hashable {
    let date: Date
    let category: String
    let isIncome: Bool
}

private struct FilteredDailyCategoryPoint: Identifiable {
    let date: Date
    var amount: Int
    let category: String
    let color: Color
    let isIncome: Bool
    var id: String { "\(date.timeIntervalSince1970)-\(category)-\(isIncome)" }
}

private struct FilteredBarChart: View {
    let series: [FilteredDailyCategoryPoint]

    private var colorMap: [String: Color] {
        var map: [String: Color] = [:]
        for point in series {
            if map[point.category] == nil {
                map[point.category] = point.color
            }
        }
        return map
    }

    private var colorScale: (domain: [String], range: [Color]) {
        let entries = colorMap.sorted { $0.key < $1.key }
        return (entries.map { $0.key }, entries.map { $0.value })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("日別収支（フィルター結果）")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Chart(series) { point in
                BarMark(
                    x: .value("日", point.date, unit: .day),
                    y: .value("金額", point.amount)
                )
                .foregroundStyle(by: .value("カテゴリ", point.category))
                .cornerRadius(3)
            }
            .chartForegroundStyleScale(domain: colorScale.domain, range: colorScale.range)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisTick()
                    AxisValueLabel(format: .dateTime.day().locale(Locale(identifier: "ja_JP")))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { v in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.2))
                    AxisTick()
                    AxisValueLabel {
                        if let n = v.as(Int.self) {
                            Text(currency(n))
                        }
                    }
                }
            }
            .frame(height: 220)
            .luxCard()
        }
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        let prefix = n < 0 ? "-¥" : "¥"
        return prefix + (f.string(from: abs(n) as NSNumber) ?? "\(n)")
    }
}

// 小型タグチップ（3文字 + … で省略）
struct TagMiniChip: View {
    let text: String
    var body: some View {
        let shown = text.count > 3 ? String(text.prefix(3)) + "…" : text
        Text(shown)
            .font(.system(size:8))
            .lineLimit(1)
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background(Capsule().fill(Color.secondary.opacity(0.12)))
    }
}
