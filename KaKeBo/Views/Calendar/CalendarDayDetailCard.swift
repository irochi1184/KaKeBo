//
//  Views/Calendar/CalendarDayDetailCard.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/10/19.
//

import SwiftUI

struct CalendarDayDetailCard: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var dayNotes: DayNotesStore
    @EnvironmentObject var themeStore: ThemeStore

    let date: Date
    let accent: Color

    @State private var editingTx: Transaction? = nil
    @State private var editingSharedTx: SharedTransaction? = nil
    @State private var showAdd = false
    @State private var showAddTodoSheet = false
    @State private var pendingNewTitle: String = ""
    @Environment(\.appVisualStyle) private var visualStyle

    private var cal: Calendar { .current }

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

    private var dayTodos: [CalendarTodo] {
        todoStore.todos(on: date)
    }

    var body: some View {
        VStack(spacing: 8) {
            header

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
            .listRowBackground(FlatListRowBackground())
            .scrollContentBackground(.hidden)
            .frame(maxHeight: .infinity)
        }
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
            .presentationDetents([.height(200)])
            .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack {
            Label(dateTitle(date), systemImage: "calendar")
                .font(.headline)
            Spacer()
            Button {
                pendingNewTitle = ""
                showAddTodoSheet = true
            } label: {
                Image(systemName: "checklist")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .accessibilityLabel("この日にToDoを追加")

            Button {
                showAdd = true
            } label: {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.20))
                        .frame(width: 34, height: 34)
                        .overlay(
                            Circle().stroke(.white.opacity(0.25), lineWidth: 0.8)
                        )
                         .shadow(color: .black.opacity(visualStyle == .business ? 0 : 0.1), radius: visualStyle == .business ? 0 : 3, y: visualStyle == .business ? 0 : 2)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("取引を追加")
        }
    }

    private var currentSharedLedger: SharedLedger? {
        ledgerContext.currentSharedLedger(from: sharedLedgerStore)
    }

    private var personalTransactionSection: some View {
        Group {
            if personalDayTx.isEmpty {
                emptyTransactionMessage
            } else {
                ForEach(personalDayTx) { tx in
                    if let cat = store.categories.first(where: { $0.id == tx.categoryId }) {
                        Button { editingTx = tx } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(cat.color.opacity(0.12))
                                    Image(systemName: cat.symbolName)
                                        .foregroundStyle(cat.color)
                                }
                                .frame(width: 32, height: 32)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cat.name)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    if !tx.memo.isEmpty {
                                        Text(tx.memo)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
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
                            Button(role: .destructive) {
                                store.deleteTransactions(with: [tx.id])
                            } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private var sharedTransactionSection: some View {
        Group {
            if sharedDayTx.isEmpty {
                emptyTransactionMessage
            } else {
                ForEach(sharedDayTx) { tx in
                    Button { editingSharedTx = tx } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(sharedColor(for: tx).opacity(0.12))
                                Image(systemName: sharedSymbol(for: tx))
                                    .foregroundStyle(sharedColor(for: tx))
                            }
                            .frame(width: 32, height: 32)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(sharedCategoryName(for: tx))
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                if let memo = tx.memo, !memo.isEmpty {
                                    Text(memo)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(currency(tx.amount))
                                .foregroundStyle(tx.type == .income ? .green : .primary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyTransactionMessage: some View {
        HStack {
            Image(systemName: "tray").foregroundStyle(.secondary)
            Text("この日の取引はありません").foregroundStyle(.secondary)
        }
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "JPY"
        f.maximumFractionDigits = 0
        return f.string(from: n as NSNumber) ?? "¥\(n)"
    }

    private func dateTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .init(identifier: "ja_JP")
        f.dateFormat = "M/d(EEE)"
        return f.string(from: date)
    }

    private func sharedCategory(for tx: SharedTransaction) -> SharedCategory? {
        guard let ledger = currentSharedLedger else { return nil }
        let sharedCategories = sharedLedgerStore.categoriesByLedger[ledger.id] ?? []
        if let cid = tx.categoryId {
            return sharedCategories.first(where: { $0.id == cid })
        }
        return sharedCategories.first(where: { $0.name == tx.categoryName })
    }

    private func sharedCategoryName(for tx: SharedTransaction) -> String {
        sharedCategory(for: tx)?.name ?? tx.categoryName
    }

    private func sharedColor(for tx: SharedTransaction) -> Color {
        let hex = sharedCategory(for: tx)?.colorHex ?? tx.categoryColorHex
        return Color.fromHex(hex) ?? .gray
    }

    private func sharedSymbol(for tx: SharedTransaction) -> String {
        sharedCategory(for: tx)?.icon ?? "tag.fill"
    }
}
