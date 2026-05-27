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
    @Environment(\.colorScheme) private var scheme

    @State private var selectedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
    }()

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

    // 今月の予算マップ
    private var budgetMap: [UUID: Int] {
        var dict: [UUID: Int] = [:]
        for b in store.budgets where b.monthId == monthId {
            dict[b.categoryId] = b.limitAmount
        }
        return dict
    }

    private var totalBudget: Int {
        budgetMap.values.reduce(0, +)
    }

    private var totalExpense: Int {
        expenseByCategory.values.reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // 月選択ヘッダー
                    monthSelector

                    // 全体サマリー
                    overallSummaryCard

                    // 前月コピーボタン
                    if budgetMap.isEmpty {
                        copyFromPreviousButton
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

    private var copyFromPreviousButton: some View {
        Button {
            let cal = Calendar.current
            if let prev = cal.date(byAdding: .month, value: -1, to: selectedMonth) {
                let f = DateFormatter()
                f.locale = Locale(identifier: "ja_JP")
                f.dateFormat = "yyyy-MM"
                let prevMonthId = f.string(from: prev)
                store.copyBudgetsFromPreviousMonth(to: monthId, from: prevMonthId)
            }
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

    // MARK: - カテゴリ別

    private var categoryBudgetList: some View {
        VStack(spacing: 10) {
            ForEach(store.categories) { category in
                CategoryBudgetRow(
                    category: category,
                    expense: expenseByCategory[category.id] ?? 0,
                    budget: budgetMap[category.id],
                    accent: accent,
                    scheme: scheme,
                    onBudgetChanged: { newAmount in
                        store.setBudget(monthId: monthId, categoryId: category.id, limitAmount: newAmount)
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
    let accent: Color
    let scheme: ColorScheme
    let onBudgetChanged: (Int) -> Void

    @State private var isEditing = false
    @State private var editText = ""

    private var ratio: Double? {
        guard let b = budget, b > 0 else { return nil }
        return Double(expense) / Double(b)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                // カテゴリアイコン
                Image(systemName: category.symbolName)
                    .foregroundStyle(category.color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 4) {
                        Text(currency(expense))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(overBudget ? .red : .primary)
                        if let b = budget {
                            Text("/ \(currency(b))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

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
            }

            // プログレスバー
            if let r = ratio {
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
        guard let b = budget, b > 0 else { return false }
        return expense > b
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}
