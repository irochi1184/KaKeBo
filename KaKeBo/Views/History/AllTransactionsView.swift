//
//  Views/History/AllTransactionsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/05.
//

import SwiftUI

struct AllTransactionsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
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
    
    // タグの正規化（検索・比較用）：8文字・lowercased
    private func normTag(_ raw: String) -> String {
        String(raw.prefix(8)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    // 取引の正規化済みタグ配列
    private func normTags(of tx: Transaction) -> [String] {
        tx.tags.map { normTag($0) }
    }
    // 全取引から重複を除いた全タグ（表示用は原文8文字切り詰め。内部キーは lowercased 8文字）
    private var allTagsForFilter: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for t in store.transactions.flatMap({ $0.tags }) {
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
                SearchHeader(
                    text: $searchText,
                    isFiltering: isFiltering,
                    accent: accent,
                    onTapFilter: { showFilter = true },
                    onClear: resetFilters
                )
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 6)
                
                // サマリー
                SummaryBar(
                    totalIncome: filteredIncomeTotal,
                    totalExpense: filteredExpenseTotal,
                    count: filtered.count,
                    accent: accent
                )
                .padding(.horizontal)
                .padding(.bottom, 6)
                
                // 一覧（タップで編集シートを開く）
                List {
                    ForEach(filtered) { tx in
                        if let cat = store.categories.first(where: { $0.id == tx.categoryId }) {
                            Button {
                                editingTx = tx
                            } label: {
                                HistoryRow(tx: tx, category: cat)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listStyle(.plain)
            }
            .background(themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if ledgerContext.isRestored {
                    ToolbarItem(placement: .topBarLeading) {
                        LedgerModePicker()
                    }
                }
            }
        }
        .sheet(isPresented: $showFilter) {
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
        .sheet(item: $editingTx) { tx in
            EditTransactionView(transaction: tx)
                .environmentObject(store)
        }
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
    var filtered: [Transaction] {
        var items = store.transactions
        
        // キーワード検索：メモ / カテゴリ名 / タグ
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter { tx in
                let memoHit = tx.memo.lowercased().contains(q)
                let catName = store.categories.first(where: { $0.id == tx.categoryId })?.name.lowercased() ?? ""
                let tagHit  = normTags(of: tx).contains { $0.contains(q) }
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
                let txTags = Set(normTags(of: tx))
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
    
    var filteredIncomeTotal: Int { filtered.filter { $0.type == .income }.reduce(0) { $0 + $1.amount } }
    var filteredExpenseTotal: Int { filtered.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount } }
    
    var isFiltering: Bool {
        if !searchText.isEmpty { return true }
        if selectedType != nil { return true }
        if !selectedCategoryIDs.isEmpty { return true }
        if dateFrom != nil || dateTo != nil { return true }
        if minAmount != nil || maxAmount != nil { return true }
        if !selectedTags.isEmpty { return true }
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

// MARK: - 行表示

private struct HistoryRow: View {
    let tx: Transaction
    let category: Category
    
    // 表示用に 8文字へ正規化 → 3文字+… にするのはチップ側
    private var displayTags: [String] {
        tx.tags.map { String($0.prefix(8)) }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // 左：カテゴリアイコン
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(category.color.opacity(0.12))
                Image(systemName: category.symbolName)
                    .foregroundStyle(category.color)
            }
            .frame(width: 36, height: 36)
            
            // 中央：カテゴリ名 + タグ（横並び）
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
                    Text(tx.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            // 右：金額と日付
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountStr(tx))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tx.type == .income ? .green : .primary)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(dateStr(tx.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
    
    private func amountStr(_ tx: Transaction) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        let sign = tx.type == .expense ? "-" : "+"
        return sign + "¥" + (f.string(from: tx.amount as NSNumber) ?? "\(tx.amount)")
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
                    Picker("種別", selection: Binding(
                        get: { selectedType ?? .none },
                        set: { newValue in selectedType = (newValue == .none) ? nil : newValue }
                    )) {
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
