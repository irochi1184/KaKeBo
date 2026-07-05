//
//  Views/Budget/BudgetTabView.swift
//  KaKeBo
//
//  カテゴリごとの予算管理タブ
//

import SwiftUI

struct BudgetTabView: View {
    @Binding var showSideMenu: Bool
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var monthStartStore: MonthStartStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var purchase: PurchaseManager
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @Environment(\.colorScheme) private var scheme

    @State private var selectedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

    // 一括設定の確認ダイアログ用
    @State private var showCopyBudgetConfirm = false
    @State private var showApplyExpenseConfirm = false

    // カテゴリ並び替え順
    @AppStorage("budget.sortOrder") private var sortOrderRaw: String = BudgetSortOrder.custom.rawValue
    private var sortOrder: BudgetSortOrder { BudgetSortOrder(rawValue: sortOrderRaw) ?? .custom }

    // タップしたカテゴリの支出一覧シート
    @State private var detailCategory: Category?

    private var monthResolver: MonthStartResolver { monthStartStore.resolver() }
    private var accent: Color { themeStore.theme.accentColor(for: scheme) }

    private var monthId: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM"
        return f.string(from: selectedMonth)
    }

    // 今月のカテゴリ別支出
    private var expenseByCategory: [UUID: Int] {
        let range = monthResolver.monthRange(for: selectedMonth)
        var dict: [UUID: Int] = [:]
        let txs = store.transactions.filter { $0.type == .expense && $0.date >= range.lowerBound && $0.date < range.upperBound }
        for tx in txs {
            dict[tx.categoryId, default: 0] += tx.amount
        }
        return dict
    }

    // 今月の予算マップ（カテゴリ → 予算）
    private var budgetByCategory: [UUID: Budget] {
        var dict: [UUID: Budget] = [:]
        for b in store.budgets where b.monthId == monthId {
            dict[b.categoryId] = b
        }
        return dict
    }

    // 有効な予算のみ合計
    private var totalBudget: Int {
        budgetByCategory.values.filter { $0.isEnabled }.reduce(0) { $0 + $1.limitAmount }
    }

    private var totalExpense: Int {
        expenseByCategory.values.reduce(0, +)
    }

    // 先月のカテゴリ別支出（「先月の支出を予算に設定」用）
    private var lastMonthExpenseByCategory: [UUID: Int] {
        guard let prev = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) else { return [:] }
        let range = monthResolver.monthRange(for: prev)
        var dict: [UUID: Int] = [:]
        for tx in store.transactions where tx.type == .expense && tx.date >= range.lowerBound && tx.date < range.upperBound {
            dict[tx.categoryId, default: 0] += tx.amount
        }
        return dict
    }

    private var hasLastMonthExpense: Bool {
        lastMonthExpenseByCategory.values.contains { $0 > 0 }
    }

    // 並び替え後のカテゴリ一覧
    private var sortedCategories: [Category] {
        let cats = store.categories
        switch sortOrder {
        case .custom:
            return cats
        case .budgetDesc:
            // 予算が高い順（未設定は末尾）
            return cats.sorted { (budgetByCategory[$0.id]?.limitAmount ?? -1) > (budgetByCategory[$1.id]?.limitAmount ?? -1) }
        case .expenseDesc:
            // 支出が多い順
            return cats.sorted { (expenseByCategory[$0.id] ?? 0) > (expenseByCategory[$1.id] ?? 0) }
        }
    }

    /// 指定カテゴリの当月の支出取引（新しい順）
    private func monthlyExpenses(for categoryId: UUID) -> [Transaction] {
        let range = monthResolver.monthRange(for: selectedMonth)
        return store.transactions
            .filter { $0.type == .expense && $0.categoryId == categoryId && $0.date >= range.lowerBound && $0.date < range.upperBound }
            .sorted { $0.date > $1.date }
    }

    // MARK: - 一括設定アクション

    /// 先月の予算をコピー（既存ありなら確認）
    private func handleCopyPreviousBudget() {
        if budgetByCategory.isEmpty {
            copyPreviousBudget()
        } else {
            showCopyBudgetConfirm = true
        }
    }

    private func copyPreviousBudget() {
        guard let prev = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) else { return }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM"
        store.copyBudgetsFromPreviousMonth(to: monthId, from: f.string(from: prev))
    }

    /// 先月の支出をまるまる予算に設定（既存ありなら確認）
    private func handleApplyLastMonthExpense() {
        if budgetByCategory.isEmpty {
            applyLastMonthExpense()
        } else {
            showApplyExpenseConfirm = true
        }
    }

    private func applyLastMonthExpense() {
        store.applyExpensesAsBudgets(monthId: monthId, expenseByCategory: lastMonthExpenseByCategory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 月選択ヘッダー
                    monthSelector

                    // 全体サマリー
                    overallSummaryCard

                    // 予算未設定時のクイック設定ボタン
                    if budgetByCategory.isEmpty {
                        quickSetupButtons
                    }

                    // カテゴリ別予算リスト
                    categoryBudgetList
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
            }
            .background(themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea())
            .navigationTitle("予算")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showSideMenu = true }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            handleApplyLastMonthExpense()
                        } label: {
                            Label("先月の支出を予算に設定", systemImage: "arrow.down.circle")
                        }
                        .disabled(!hasLastMonthExpense)

                        Button {
                            handleCopyPreviousBudget()
                        } label: {
                            Label("先月の予算をコピー", systemImage: "doc.on.doc")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
            .confirmationDialog(
                "先月の予算で上書き",
                isPresented: $showCopyBudgetConfirm,
                titleVisibility: .visible
            ) {
                Button("上書きする", role: .destructive) { copyPreviousBudget() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("今月すでに設定済みの予算を、先月の予算で上書きします。")
            }
            .confirmationDialog(
                "先月の支出で上書き",
                isPresented: $showApplyExpenseConfirm,
                titleVisibility: .visible
            ) {
                Button("上書きする", role: .destructive) { applyLastMonthExpense() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("今月すでに設定済みの予算を、先月の支出額で上書きします。")
            }
            .sheet(item: $detailCategory) { category in
                CategoryBudgetDetailSheet(
                    category: category,
                    monthTitle: monthTitle,
                    transactions: monthlyExpenses(for: category.id),
                    budget: budgetByCategory[category.id]?.limitAmount,
                    accent: accent,
                    scheme: scheme
                )
                .environmentObject(store)
                .environmentObject(themeStore)
                .environmentObject(purchase)
                .environmentObject(sharedLedgerStore)
                .environmentObject(ledgerContext)
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - 月選択

    private var monthSelector: some View {
        HStack {
            Button {
                if let prev = Calendar.current.date(byAdding: .month, value: -1, to: selectedMonth) {
                    selectedMonth = prev
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }

            Spacer()

            Text(monthTitle)
                .font(.headline)

            Spacer()

            Button {
                if let next = Calendar.current.date(byAdding: .month, value: 1, to: selectedMonth) {
                    selectedMonth = next
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
        }
        .padding(.vertical, 8)
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: selectedMonth)
    }

    // MARK: - 全体サマリーカード

    private var overallSummaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("総予算")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(totalBudget > 0 ? currency(totalBudget) : "未設定")
                        .font(.title2.weight(.bold).monospacedDigit())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("支出合計")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(currency(totalExpense))
                        .font(.title2.weight(.bold).monospacedDigit())
                        .foregroundStyle(totalBudget > 0 && totalExpense > totalBudget ? .red : .primary)
                }
            }

            if totalBudget > 0 {
                // プログレスバー
                let ratio = Double(totalExpense) / Double(totalBudget)
                let barColor: Color = ratio > 1.0 ? .red : (ratio > 0.8 ? .orange : accent)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barColor.gradient)
                            .frame(width: geo.size.width * min(CGFloat(ratio), 1.0), height: 10)
                    }
                }
                .frame(height: 10)

                HStack {
                    Text("残り: \(currency(max(0, totalBudget - totalExpense)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(min(Double(totalExpense) / Double(max(1, totalBudget)) * 100, 999)))%")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Double(totalExpense) / Double(max(1, totalBudget)) > 1.0 ? .red : .secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : .white)
                .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.06), radius: 10, y: 5)
        )
    }

    // MARK: - 前月コピー

    private var quickSetupButtons: some View {
        VStack(spacing: 8) {
            // 先月の支出をまるまる予算にする
            if hasLastMonthExpense {
                Button {
                    applyLastMonthExpense()
                } label: {
                    Label("先月の支出を予算に設定", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(accent.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
            }

            // 先月の予算をコピー
            Button {
                copyPreviousBudget()
            } label: {
                Label("先月の予算をコピー", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - カテゴリ別

    private var categoryBudgetList: some View {
        VStack(spacing: 10) {
            // 並び替えコントロール
            HStack {
                Spacer()
                Menu {
                    Picker("並び替え", selection: $sortOrderRaw) {
                        ForEach(BudgetSortOrder.allCases) { order in
                            Text(order.title).tag(order.rawValue)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(sortOrder.title)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(accent.opacity(0.1))
                    )
                }
            }

            ForEach(sortedCategories) { category in
                let budget = budgetByCategory[category.id]
                let expense = expenseByCategory[category.id] ?? 0
                CategoryBudgetRow(
                    category: category,
                    expense: expense,
                    budget: budget?.limitAmount,
                    isEnabled: budget?.isEnabled ?? true,
                    accent: accent,
                    scheme: scheme,
                    canShowDetail: expense > 0,
                    onSelect: { detailCategory = category },
                    onBudgetChanged: { newAmount in
                        store.setBudget(monthId: monthId, categoryId: category.id, limitAmount: newAmount)
                    },
                    onToggleEnabled: { enabled in
                        store.setBudgetEnabled(monthId: monthId, categoryId: category.id, isEnabled: enabled)
                    }
                )
            }
        }
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}

// MARK: - カテゴリ別予算行

private struct CategoryBudgetRow: View {
    let category: Category
    let expense: Int
    let budget: Int?
    let isEnabled: Bool
    let accent: Color
    let scheme: ColorScheme
    let canShowDetail: Bool
    let onSelect: () -> Void
    let onBudgetChanged: (Int) -> Void
    let onToggleEnabled: (Bool) -> Void

    @State private var isEditing = false
    @State private var editText = ""

    // 予算が設定されているか
    private var hasBudget: Bool { (budget ?? 0) > 0 }

    private var ratio: Double? {
        guard let b = budget, b > 0, isEnabled else { return nil }
        return Double(expense) / Double(b)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // カテゴリアイコン＋名称＋金額（タップで支出一覧へ）
                Button(action: onSelect) {
                    HStack(spacing: 10) {
                        Image(systemName: category.symbolName)
                            .foregroundStyle(category.color)
                            .frame(width: 28)
                            .opacity(hasBudget && !isEnabled ? 0.4 : 1)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(category.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(hasBudget && !isEnabled ? .secondary : .primary)
                                // 一時停止バッジ
                                if hasBudget && !isEnabled {
                                    Text("停止中")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(Color.secondary.opacity(0.15))
                                        )
                                        .foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 4) {
                                Text(currency(expense))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(overBudget ? .red : .primary)
                                if let b = budget {
                                    Text("/ \(currency(b))")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                // 支出一覧を開けることを示すヒント
                                if canShowDetail {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canShowDetail)

                // 予算設定ボタン
                Button {
                    editText = budget.map { "\($0)" } ?? ""
                    isEditing = true
                } label: {
                    if let b = budget {
                        Text(currency(b))
                            .font(.caption.weight(.medium).monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(accent.opacity(0.1))
                            )
                    } else {
                        Text("設定")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)

                // ON/OFF トグル（予算設定済みのカテゴリのみ）
                if hasBudget {
                    Toggle("", isOn: Binding(
                        get: { isEnabled },
                        set: { onToggleEnabled($0) }
                    ))
                    .labelsHidden()
                    .tint(accent)
                    .scaleEffect(0.8)
                    .frame(width: 44)
                }
            }

            // プログレスバー
            if let r = ratio, let b = budget {
                let barColor: Color = r > 1.0 ? .red : (r > 0.8 ? .orange : category.color)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.gray.opacity(0.12))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(barColor.gradient)
                            .frame(width: geo.size.width * min(CGFloat(r), 1.0), height: 6)
                    }
                }
                .frame(height: 6)

                // 残額表示
                HStack {
                    Spacer()
                    if expense > b {
                        Text("\(currency(expense - b)) 超過")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.red)
                    } else {
                        Text("残り \(currency(b - expense))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : .white)
                .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.04), radius: 6, y: 3)
        )
        .alert("予算を設定", isPresented: $isEditing) {
            TextField("金額", text: $editText)
                .keyboardType(.numberPad)
            Button("保存") {
                let amount = Int(editText.filter(\.isNumber)) ?? 0
                onBudgetChanged(amount)
            }
            Button("削除", role: .destructive) {
                onBudgetChanged(0)
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(category.name) の月間予算を入力してください")
        }
    }

    private var overBudget: Bool {
        guard let b = budget, b > 0, isEnabled else { return false }
        return expense > b
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}

// MARK: - 並び替え順

enum BudgetSortOrder: String, CaseIterable, Identifiable {
    case custom      // 標準（カテゴリ順）
    case budgetDesc  // 予算が高い順
    case expenseDesc // 支出が多い順

    var id: String { rawValue }

    var title: String {
        switch self {
        case .custom:      return "標準"
        case .budgetDesc:  return "予算が高い順"
        case .expenseDesc: return "支出が多い順"
        }
    }
}

// MARK: - カテゴリ別 支出一覧シート

private struct CategoryBudgetDetailSheet: View {
    let category: Category
    let monthTitle: String
    let transactions: [Transaction]
    let budget: Int?
    let accent: Color
    let scheme: ColorScheme

    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var purchase: PurchaseManager
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @Environment(\.dismiss) private var dismiss

    @State private var editingTx: Transaction?

    private var total: Int { transactions.reduce(0) { $0 + $1.amount } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // サマリーバー（履歴タブ風）
                summaryBar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(themeStore.theme.backgroundColor(for: scheme))

                if transactions.isEmpty {
                    Spacer()
                    Text("この月の支出はありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List {
                        ForEach(transactions) { tx in
                            Button {
                                editingTx = tx
                            } label: {
                                BudgetExpenseRow(transaction: tx, category: category)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(themeStore.theme.backgroundColor(for: scheme))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea())
            .navigationTitle("\(category.name)・\(monthTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .sheet(item: $editingTx) { tx in
                EditTransactionView(transaction: tx)
                    .environmentObject(store)
                    .environmentObject(themeStore)
                    .environmentObject(purchase)
                    .environmentObject(sharedLedgerStore)
                    .environmentObject(ledgerContext)
            }
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(category.color.opacity(0.12))
                Image(systemName: category.symbolName)
                    .foregroundStyle(category.color)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("支出合計")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currency(total))
                    .font(.headline.weight(.bold).monospacedDigit())
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let b = budget {
                    Text("予算 \(currency(b))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    // 残額表示
                    if total > b {
                        Text("\(currency(total - b)) 超過")
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.red)
                    } else {
                        Text("残り \(currency(b - total))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(transactions.count)件")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : .white)
                .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.04), radius: 6, y: 3)
        )
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}

// MARK: - 支出明細の行（履歴タブの HistoryRow に合わせたデザイン）

private struct BudgetExpenseRow: View {
    let transaction: Transaction
    let category: Category
    @Environment(\.appExpenseColor) private var expenseColor

    private var displayTags: [String] {
        transaction.tags.map { String($0.prefix(8)) }
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

            // 中央：カテゴリ名 + タグ + メモ
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(category.name)
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

                let memo = transaction.memo.trimmingCharacters(in: .whitespacesAndNewlines)
                if !memo.isEmpty {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            // 写真プレビュー（添付があるときのみ・行の高さは変えない）
            if let photos = transaction.photoFilenames, !photos.isEmpty {
                TransactionRowPhotoPreview(filenames: photos)
            }

            // 右：金額と日付
            VStack(alignment: .trailing, spacing: 2) {
                Text(amountStr())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(expenseColor)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(dateStr(transaction.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func amountStr() -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return "-¥" + (f.string(from: transaction.amount as NSNumber) ?? "\(transaction.amount)")
    }

    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(E)"
        return f.string(from: d)
    }
}
