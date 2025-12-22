//
//  Views/Calendar/DayDetailSheet.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/23.
//

import SwiftUI

struct DayDetailSheet: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var dayNotes: DayNotesStore
    private var dayTodos: [CalendarTodo] { todoStore.todos(on: date) }
    
    let date: Date
    let accent: Color
    private var cal: Calendar { .current }

    @State private var editingTx: Transaction? = nil
    @State private var editingSharedTx: SharedTransaction? = nil
    @State private var showAdd = false
    @State private var showAddTodoSheet = false
    @State private var pendingNewTitle: String = ""

    private var personalDayTx: [Transaction] {
        store.transactions
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }

    private var sharedDayTx: [SharedTransaction] {
        guard
            ledgerContext.isShared,
            let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore)
        else { return [] }

        let txs = sharedLedgerStore.transactionsByLedger[ledger.id] ?? []
        return txs
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                List {
                    Section("この日の記録") {
                        if ledgerContext.isShared {
                            sharedTransactionSection
                        } else {
                            personalTransactionSection
                        }
                    }
                    
                    Section {
                        if dayTodos.isEmpty {
                            HStack {
                                Image(systemName: "checklist").foregroundStyle(.secondary)
                                Text("この日のToDoはありません").foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(dayTodos) { t in
                                DayTodoRow(
                                    date: date,
                                    todo: t,
                                    accent: accent,
                                    onToggle: { id in
                                        todoStore.toggle(id)
                                        todoStore.save(for: date)
                                    },
                                    onEditDue: { id, newDate in
                                        todoStore.setDue(id, newDate)
                                        todoStore.save(for: date)
                                    },
                                    onRename: { id, newTitle in
                                        todoStore.rename(id, newTitle)
                                        todoStore.save(for: date)
                                    },
                                    onDelete: { id in
                                        todoStore.delete(ids: [id])
                                        todoStore.save(for: date)
                                    }
                                )
                            }
                            .onDelete(perform: deleteTodos)
                        }
                    } header: {
                        Text("この日のToDo")
                    } footer: {
                        Button {
                            pendingNewTitle = ""
                            showAddTodoSheet = true
                        } label: {
                            Label("この日にToDoを追加", systemImage: "plus.circle.fill")
                        }
                        .tint(accent)
                    }
                    
                    Section("この日のメモ") {
                        DayNoteEditor(
                            date: date,
                            accent: accent
                        )
                    }

                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle(dateTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 編集モード切替（削除可）
                    EditButton().disabled(ledgerContext.isShared || personalDayTx.isEmpty)
                    // 追加（＋）
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent.opacity(0.2))
                }
            }
            // 編集シート
            .sheet(item: $editingTx) { tx in
                EditTransactionView(transaction: tx)
                    .environmentObject(store)
            }
            .sheet(item: $editingSharedTx) { tx in
                if let ledger = currentSharedLedger {
                    EditTransactionView(sharedLedger: ledger, transaction: tx)
                        .environmentObject(sharedLedgerStore)
                }
            }
            // その日の新規追加
            .sheet(isPresented: $showAdd) {
                AddTransactionView(
                    defaultCategoryId: store.categories.first?.id,
                    defaultDate: date,
                    defaultType: .expense
                )
                .environmentObject(store)
            }
                .sheet(isPresented: $showAddTodoSheet) {
                    AddTodoMiniSheet(
                        accent: accent,
                    title: $pendingNewTitle,
                    onAdd: {
                        let t = pendingNewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        todoStore.add(title: t, due: date)
                        todoStore.save(for: date)
                        showAddTodoSheet = false
                    },
                    onCancel: { showAddTodoSheet = false }
                )
                .presentationDetents([.height(200)])   // ← “アラート風”の小ぶりサイズ
                .presentationDragIndicator(.visible)
                .background(themeStore.theme.backgroundColor(for: scheme))
            }
            .task { await reloadSharedLedgerDataIfNeeded() }
        }
    }

    @ViewBuilder
    private var personalTransactionSection: some View {
        if personalDayTx.isEmpty {
            emptyTransactionMessage
        } else {
            ForEach(personalDayTx) { tx in
                var displayTags: [String] { tx.tags.map { String($0.prefix(8)) } }

                if let cat = store.categories.first(where: { $0.id == tx.categoryId }) {
                    Button { editingTx = tx } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(cat.color.opacity(0.12))
                                Image(systemName: cat.symbolName).foregroundStyle(cat.color)
                            }
                            .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(cat.name)
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
                                if !tx.memo.isEmpty {
                                    Text(tx.memo).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(currency(tx.amount))
                                .foregroundStyle(tx.type == .income ? .green : .primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button { editingTx = tx } label: {
                            Label("編集", systemImage: "pencil")
                        }
                        .tint(.blue)

                        Button(role: .destructive) {
                            store.deleteTransactions(with: [tx.id])
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
            .onDelete(perform: deletePersonalTransactions)
        }
    }

    @ViewBuilder
    private var sharedTransactionSection: some View {
        if sharedDayTx.isEmpty {
            emptyTransactionMessage
        } else {
            ForEach(sharedDayTx) { tx in
                Button { editingSharedTx = tx } label: {
                    sharedRow(for: tx)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyTransactionMessage: some View {
        HStack {
            Image(systemName: "calendar.badge.exclamationmark")
                .foregroundStyle(.secondary)
            Text("この日には記録がありません")
                .foregroundStyle(.secondary)
        }
    }

    private func sharedRow(for tx: SharedTransaction) -> some View {
        let color = sharedColor(for: tx)
        let symbol = sharedSymbol(for: tx)
        let memo = (tx.memo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color.opacity(0.12))
                Image(systemName: symbol).foregroundStyle(color)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(tx.categoryName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                if !memo.isEmpty {
                    Text(memo).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(currency(tx.amount))
                .foregroundStyle(tx.type == .income ? .green : .primary)
        }
        .contentShape(Rectangle())
    }
    
    private var dateTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(EEE)"
        return f.string(from: date)
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }

    private var currentSharedLedger: SharedLedger? {
        ledgerContext.currentSharedLedger(from: sharedLedgerStore)
    }

    private var sharedCategories: [SharedCategory] {
        guard let ledger = currentSharedLedger else { return [] }
        return sharedLedgerStore.categoriesByLedger[ledger.id] ?? []
    }

    private func sharedCategory(for tx: SharedTransaction) -> SharedCategory? {
        if let cid = tx.categoryId {
            return sharedCategories.first(where: { $0.id == cid })
        }
        return sharedCategories.first(where: { $0.name == tx.categoryName })
    }

    private func reloadSharedLedgerDataIfNeeded() async {
        guard ledgerContext.isShared,
              let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore) else { return }

        await sharedLedgerStore.reloadCategories(for: ledger)
        await sharedLedgerStore.reloadTransactions(for: ledger)
    }

    private func sharedColor(for tx: SharedTransaction) -> Color {
        let hex = sharedCategory(for: tx)?.colorHex ?? tx.categoryColorHex
        return Color.fromHex(hex) ?? .gray
    }

    private func sharedSymbol(for tx: SharedTransaction) -> String {
        sharedCategory(for: tx)?.icon ?? "tag.fill"
    }

    private func deletePersonalTransactions(at offsets: IndexSet) {
        let ids = offsets.map { personalDayTx[$0].id }
        store.deleteTransactions(with: ids)
    }

    private func deleteTodos(at offsets: IndexSet) {
        let ids = offsets.map { dayTodos[$0].id }
        todoStore.delete(ids: ids)
        todoStore.save(for: date)
    }
    
}
