//
//  Views/Calendar/DayDetailSheet.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/23.
//

import SwiftUI

import SwiftUI

struct DayDetailSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var todoStore: TodoStore
    private var dayTodos: [CalendarTodo] { todoStore.todos(on: date) }
    
    let date: Date
    private var cal: Calendar { .current }
    
    @State private var editingTx: Transaction? = nil
    @State private var showAdd = false
    @State private var showAddTodoAlert = false
    @State private var pendingNewTitle: String = ""
    
    private var dayTx: [Transaction] {
        store.transactions
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                List {
                    Section("この日の記録") {
                        if dayTx.isEmpty {
                            HStack {
                                Image(systemName: "calendar.badge.exclamationmark")
                                    .foregroundStyle(.secondary)
                                Text("この日には記録がありません")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(dayTx) { tx in
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
                                                Text(cat.name).font(.subheadline.weight(.medium))
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
                                    }
                                }
                            }
                            // 右上の EditButton での削除にも対応（取引用）
                            .onDelete(perform: delete)
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
                            .onDelete(perform: delete)
                        }
                    } header: {
                        Text("この日のToDo")
                    } footer: {
                        Button {
                            pendingNewTitle = ""
                            showAddTodoAlert = true
                        } label: {
                            Label("この日にToDoを追加", systemImage: "plus.circle.fill")
                        }
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
                    EditButton().disabled(dayTx.isEmpty)
                    // 追加（＋）
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .imageScale(.large)
                    }
                }
            }
            // 編集シート
            .sheet(item: $editingTx) { tx in
                EditTransactionView(transaction: tx)
                    .environmentObject(store)
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
            .alert("ToDoを追加", isPresented: $showAddTodoAlert) {
                TextField("タイトル", text: $pendingNewTitle)
                Button("追加") {
                    let t = pendingNewTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    todoStore.add(title: t, due: date) // この日を既定の期日に
                    todoStore.save(for: date)
                }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この日のToDoを追加します")
            }
        }
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
    
    // EditButton（編集モード）時の削除（確認なし）
    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { dayTx[$0].id }
        store.deleteTransactions(with: ids)
    }
    
    private struct DayTodoRow: View {
        let date: Date
        let todo: CalendarTodo
        let onToggle: (UUID) -> Void
        let onEditDue: (UUID, Date?) -> Void
        let onRename: (UUID, String) -> Void
        let onDelete: (UUID) -> Void
        
        @State private var showDuePicker = false
        @State private var tempDue: Date = Date()
        
        @State private var isRenaming = false
        @State private var tempTitle = ""
        @FocusState private var titleFocused: Bool
        
        private var cal: Calendar { .current }
        
        var body: some View {
            HStack(spacing: 10) {
                Button { onToggle(todo.id) } label: {
                    Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(todo.done ? .green : .secondary)
                }
                .buttonStyle(.plain)
                
                VStack(alignment: .leading, spacing: 4) {
                    // ▼ 名称：タップで編集モードに
                    if isRenaming {
                        HStack(spacing: 8) {
                            TextField("タイトル", text: $tempTitle)
                                .textFieldStyle(.roundedBorder)
                                .focused($titleFocused)
                                .submitLabel(.done)
                                .onSubmit { commitRename() }
                            
                            Button {
                                commitRename()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(.plain)
                        }
                        .onAppear {
                            // 初期値をセットしてフォーカス
                            tempTitle = todo.title
                            titleFocused = true
                        }
                    } else {
                        Text(todo.title)
                            .font(.subheadline.weight(.medium))
                            .strikethrough(todo.done, pattern: .solid, color: .secondary)
                            .foregroundStyle(todo.done ? .secondary : .primary)
                            .onTapGesture {
                                // タイトルをタップで編集開始
                                isRenaming = true
                            }
                    }
                    
                    // ▼ 期日バッジ
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock").foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            if let due = todo.due {
                                if cal.isDateInToday(due) {
                                    Circle().fill(Color.blue).frame(width: 6, height: 6)
                                }
                                Text(dueLabel(due))
                                    .font(.caption)
                                    .foregroundStyle(isOverdue(due) && !todo.done ? .red : .secondary)
                            } else {
                                Text("期日なし").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.thinMaterial))
                        .onTapGesture {
                            tempDue = todo.due ?? date
                            showDuePicker = true
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
            // ▼ 右→左スワイプで削除
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    onDelete(todo.id)
                } label: {
                    Label("削除", systemImage: "trash")
                }
            }
            .popover(isPresented: $showDuePicker, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                DuePopover(
                    month: date,
                    tempDate: $tempDue,
                    onSave: { newDate in
                        onEditDue(todo.id, newDate)
                        showDuePicker = false
                    },
                    onClear: {
                        onEditDue(todo.id, nil)
                        showDuePicker = false
                    }
                )
                .presentationDetents([.medium])
            }
        }
        
        
        private func commitRename() {
            let t = tempTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, t != todo.title {
                onRename(todo.id, t)
            }
            isRenaming = false
            titleFocused = false
        }
        
        private func dueLabel(_ d: Date) -> String {
            let f = DateFormatter(); f.locale = .init(identifier:"ja_JP"); f.dateFormat = "M/d(EEE)"
            return f.string(from: d)
        }
        private func isOverdue(_ d: Date) -> Bool {
            let today = cal.startOfDay(for: Date())
            let due   = cal.startOfDay(for: d)
            return due < today
        }
    }
}

