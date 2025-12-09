//
//  Views/History/AllTransactionsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/05.
//

import SwiftUI
import CloudKit

struct AllTransactionsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
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

    // 共有用の絞り込み状態
    @State private var sharedSelectedType: SharedTransactionType? = nil
    @State private var sharedSelectedCategoryIDs: Set<CKRecord.ID> = []
    @State private var sharedDateFrom: Date? = nil
    @State private var sharedDateTo: Date? = nil
    @State private var sharedMinAmount: Int? = nil
    @State private var sharedMaxAmount: Int? = nil
    @State private var sharedSelectedTags: Set<String> = []
    @State private var editingSharedTx: SharedTransaction? = nil
    
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
            Group {
                if ledgerContext.isRestored {
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
                                onTapFilter: { showFilter = true },
                                onClear: resetFilters
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

                        contentList
                    }
                } else {
                    LedgerLoadingView()
                }
            }
            .background(themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showFilter) {
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
                    selectedTags: $sharedSelectedTags
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
        .task { await ledgerContext.restoreIfNeeded(sharedLedgerStore: sharedLedgerStore) }
        .task(id: ledgerContext.selectedSharedLedgerId) { await reloadSharedLedgerDataIfNeeded() }
    }
}

private extension AllTransactionsView {
    @ViewBuilder
    var contentList: some View {
        List {
            ForEach(displayed) { item in
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
            }
        }
        .listStyle(.plain)
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
}

// MARK: - 検索＋フィルタ ヘッダ

private struct SearchHeader: View {
    @Binding var text: String
    let isFiltering: Bool
    let accent: Color
    let onTapFilter: () -> Void
    let onClear: () -> Void
    
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
        return items.sorted { $0.date > $1.date }
    }

    var filteredShared: [SharedTransaction] {
        guard let ledger = currentSharedLedger else { return [] }
        var items = sharedLedgerStore.transactionsByLedger[ledger.id] ?? []
        let categories = sharedLedgerStore.categoriesByLedger[ledger.id] ?? []

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
        return items.sorted { $0.date > $1.date }
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

    func resetFilters() {
        searchText = ""
        selectedType = nil
        selectedCategoryIDs = []
        dateFrom = nil
        dateTo = nil
        minAmount = nil
        maxAmount = nil
        selectedTags.removeAll()

        sharedSelectedType = nil
        sharedSelectedCategoryIDs = []
        sharedDateFrom = nil
        sharedDateTo = nil
        sharedMinAmount = nil
        sharedMaxAmount = nil
        sharedSelectedTags.removeAll()
    }
}

// MARK: - サマリー

private struct SummaryBar: View {
    let totalIncome: Int
    let totalExpense: Int
    let count: Int
    let accent: Color

    var body: some View {
        HStack(spacing: 14) {
            StatPill(title: "収入", value: totalIncome, color: .green)
            StatPill(title: "支出", value: totalExpense, color: .red)
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
                    .foregroundStyle(content.isIncome ? .green : .primary)
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
    
    // ★ タグ
    let allTags: [String]                    // 表示用（最大8文字）
    @Binding var selectedTags: Set<String>   // 正規化キー lowercased 8文字
    
    @Environment(\.dismiss) private var dismiss
    
    // ★ 表示→内部キー変換
    private func key(_ display: String) -> String {
        String(display.prefix(8)).lowercased()
    }
    
    var body: some View {
        NavigationStack {
            Form {
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

private struct SharedFilterSheet: View {
    let allCategories: [SharedCategory]
    @Binding var selectedType: SharedTransactionType?
    @Binding var selectedCategoryIDs: Set<CKRecord.ID>
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var minAmount: Int?
    @Binding var maxAmount: Int?

    let allTags: [String]
    @Binding var selectedTags: Set<String>

    @Environment(\.dismiss) private var dismiss

    private func key(_ display: String) -> String {
        String(display.prefix(8)).lowercased()
    }

    private func color(for cat: SharedCategory) -> Color {
        Color.fromHex(cat.colorHex) ?? .accentColor
    }

    var body: some View {
        NavigationStack {
            Form {
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
