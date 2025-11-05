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
    
    // 編集シート
    @State private var editingTx: Transaction? = nil
    
    // フィルタシート
    @State private var showFilter = false
    
    var body: some View {
        let accent = themeStore.theme.accentColor(for: scheme)
        NavigationStack {
            VStack(spacing: 0) {
                
                // 🔎 検索バー + フィルタを横並び
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
        }
        .sheet(isPresented: $showFilter) {
            FilterSheet(
                allCategories: store.categories,
                selectedType: $selectedType,
                selectedCategoryIDs: $selectedCategoryIDs,
                dateFrom: $dateFrom,
                dateTo: $dateTo,
                minAmount: $minAmount,
                maxAmount: $maxAmount
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
                TextField("メモ・カテゴリ名を検索", text: $text)
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
        
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            items = items.filter { tx in
                let memoHit = tx.memo.lowercased().contains(q)
                let catName = store.categories.first(where: { $0.id == tx.categoryId })?.name.lowercased() ?? ""
                return memoHit || catName.contains(q)
            }
        }
        if let kind = selectedType {
            items = items.filter { $0.type == kind }
        }
        if !selectedCategoryIDs.isEmpty {
            items = items.filter { selectedCategoryIDs.contains($0.categoryId) }
        }
        if let from = dateFrom {
            items = items.filter { $0.date >= Calendar.current.startOfDay(for: from) }
        }
        if let to = dateTo {
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: to) ?? to
            items = items.filter { $0.date <= endOfDay }
        }
        if let lo = minAmount {
            items = items.filter { $0.amount >= lo }
        }
        if let hi = maxAmount {
            items = items.filter { $0.amount <= hi }
        }
        return items.sorted { $0.date > $1.date }
    }
    
    var filteredIncomeTotal: Int {
        filtered.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
    }
    var filteredExpenseTotal: Int {
        filtered.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
    }
    var isFiltering: Bool {
        if !searchText.isEmpty { return true }
        if selectedType != nil { return true }
        if !selectedCategoryIDs.isEmpty { return true }
        if dateFrom != nil || dateTo != nil { return true }
        if minAmount != nil || maxAmount != nil { return true }
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
                Text(amountStr(tx))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tx.type == .income ? .green : .primary)
                    .monospacedDigit()
                Text(dateStr(tx.date))
                    .font(.caption2).foregroundStyle(.secondary)
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
    
    @Environment(\.dismiss) private var dismiss
    
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
                
                Section("金額範囲 (¥)") {
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
