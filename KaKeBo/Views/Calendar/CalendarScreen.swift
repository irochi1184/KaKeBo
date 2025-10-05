//
//  Views/Calendar/CalendarScreen.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/23.
//

import SwiftUI

struct CalendarScreen: View {
    @EnvironmentObject var store: DataStore
    public var cal: Calendar { .current }
    
    // 年月
    @State private var month: Date = Calendar.current.date(from:Calendar.current.dateComponents([.year,.month], from: .now)
    ) ?? .now
    
    // どのシートを出すか（単一ソース・オブ・トゥルース）
    @State private var sheet: Sheet?
    
    enum Sheet: Identifiable, Equatable {
        case detail(Date)
        case add(Date)
        case addPrefilled(date: Date, categoryId: UUID?, amount: Int?, memo: String?) // ← 追加
        var id: String {
            switch self {
            case .detail(let d): return "detail-\(d.timeIntervalSince1970)"
            case .add(let d): return "add-\(d.timeIntervalSince1970)"
            case .addPrefilled(let date, _, _, _): return "addp-\(date.timeIntervalSince1970)"
            }
        }
    }
    
    // ★ 月別ToDo（この画面ローカルで保持・保存）
    @State private var todos: [CalendarTodo] = []
    @State private var newTodoTitle: String = ""
    @State private var showOnlyUndone: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                
                // 年月ヘッダー
                HStack(spacing: 12) {
                    Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                        Image(systemName: "chevron.left.circle.fill").font(.title3).symbolRenderingMode(.hierarchical)
                    }
                    Spacer()
                    Text(title(month))
                        .font(.headline.weight(.semibold))
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.thinMaterial))
                    Spacer()
                    Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                        Image(systemName: "chevron.right.circle.fill").font(.title3).symbolRenderingMode(.hierarchical)
                    }
                }
                .padding(.horizontal)
                
                // 曜日ヘッダー
                HStack {
                    ForEach(weekdaySymbolsJP, id: \.self) { w in
                        Text(w).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                
                // 月グリッド
                CalendarMonthGrid(
                    month: month,
                    expenseBuckets: expenseBuckets,
                    incomeBuckets: incomeBuckets,
                    maxExpense: maxExpenseInMonth,
                    maxIncome: maxIncomeInMonth,
                    todoCounts: todoDueCounts,
                    onTapDay: { day in
                        sheet = .detail(day)      // ← 1タップは必ず詳細
                    },
                    onLongPressDay: { day in
                        sheet = .add(day)         // ← 長押しは追加
                    }
                )
                .padding(.horizontal)
                
                TodoCard(
                    month: month,
                    todos: filteredTodos,                 // ← 未完のみ切り替え対応
                    onToggle: { id in toggleTodo(id) },
                    onDelete: { offsets in deleteTodos(offsets) },
                    onEditDue: { id, newDate in setDue(id, newDate) },
                    newTitle: $newTodoTitle,
                    onAdd: { addTodo() },
                    showOnlyUndone: $showOnlyUndone,
                    onQuickAdd: { tapped in handleQuickAdd(tapped) } // ← プリセット起動
                )
                .padding(.horizontal)
                
                Spacer(minLength: 8)
            }
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .add(.now)        // 右上＋は今日で追加
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $sheet) { s in
                switch s {
                case .detail(let date):
                    DayDetailSheet(date: date).environmentObject(store)
                    
                case .add(let date):
                    AddTransactionView(
                        defaultCategoryId: store.categories.first?.id,
                        defaultDate: date
                    )
                    .environmentObject(store)
                    
                case .addPrefilled(let date, let categoryId, let amount, let memo):
                    let targetCat = categoryId ?? store.categories.first?.id
                    let initialAmount = amount
                    let initialMemo = memo
                    AddTransactionView(
                        defaultCategoryId: targetCat,
                        defaultAmount: initialAmount,
                        defaultDate: date,
                        defaultType: .expense,
                        defaultMemo: initialMemo
                    )
                    .environmentObject(store)
                }
            }
            .onAppear { loadTodos(for: month) }                                  // ★ 初回ロード
            .onChange(of: month) {                                               // ★ 月が変わったらロード
                loadTodos(for: month)
            }
        }
    }
    
    // MARK: - 集計
    private var transactionsThisMonth: [Transaction] {
        store.transactions.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    
    /// 日別 “支出” 合計
    private var expenseBuckets: [Date: Int] {
        var dict: [Date: Int] = [:]
        for tx in transactionsThisMonth where tx.type == .expense {
            let key = cal.startOfDay(for: tx.date)
            dict[key, default: 0] += tx.amount
        }
        return dict
    }
    
    /// 日別 “収入” 合計
    private var incomeBuckets: [Date: Int] {
        var dict: [Date: Int] = [:]
        for tx in transactionsThisMonth where tx.type == .income {
            let key = cal.startOfDay(for: tx.date)
            dict[key, default: 0] += tx.amount
        }
        return dict
    }
    
    /// 今月の最大支出・最大収入（セルの濃淡に使用）
    private var maxExpenseInMonth: Int { expenseBuckets.values.max() ?? 0 }
    private var maxIncomeInMonth:  Int { incomeBuckets.values.max() ?? 0 }
    
    private func title(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }
    
    private var weekdaySymbolsJP: [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        return f.shortStandaloneWeekdaySymbols
    }
    
    // MARK: - ToDo 永続化（UserDefaultsに月キーで保存）
    private func key(for month: Date) -> String {
        let f = DateFormatter(); f.locale = .init(identifier:"ja_JP"); f.dateFormat = "yyyy-MM"
        return "kakebo.todos.\(f.string(from: month))"
    }
    private func loadTodos(for month: Date) {
        let k = key(for: month)
        if let data = UserDefaults.standard.data(forKey: k),
           let items = try? JSONDecoder().decode([CalendarTodo].self, from: data) {
            todos = items
        } else {
            todos = []
        }
        ensureRecurringTodos(for: month)
    }
    private func saveTodos() {
        let k = key(for: month)
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: k)
        }
    }
    
    // MARK: - ToDo 操作
    private var filteredTodos: [CalendarTodo] {
        showOnlyUndone ? todos.filter { !$0.done } : todos
    }
    private func addTodo() {
        let title = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        todos.insert(.init(title: title, done: false, due: nil), at: 0)
        newTodoTitle = ""
        saveTodos()
    }
    private func toggleTodo(_ id: UUID) {
        guard let i = todos.firstIndex(where: {$0.id == id}) else { return }
        todos[i].done.toggle()
        saveTodos()
    }
    private func deleteTodos(_ offsets: IndexSet) {
        let ids = offsets.map { filteredTodos[$0].id }
        todos.removeAll { ids.contains($0.id) }
        saveTodos()
    }
    private func setDue(_ id: UUID, _ due: Date?) {
        guard let i = todos.firstIndex(where: {$0.id == id}) else { return }
        todos[i].due = due
        saveTodos()
    }
    // ▼ ToDoの件数を“日付ごと”に集計（未完了のみ）
    private var todoDueCounts: [Date: Int] {
        var dict: [Date: Int] = [:]
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let end   = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        
        // この月のToDoだけを対象（UserDefaultsに保存している想定なら loadTodos(for:) 済み）
        for t in todos where t.done == false {
            if let d = t.due {
                // 当該月内だけカウント
                if d >= start && d <= end {
                    let key = cal.startOfDay(for: d)
                    dict[key, default: 0] += 1
                }
            }
        }
        return dict
    }
    
    @AppStorage("kakebo.recurring.templates") private var templatesData: Data = Data()
    private var templates: [RecurringTodoTemplate] {
        (try? JSONDecoder().decode([RecurringTodoTemplate].self, from: templatesData)) ?? []
    }
    
    private func ensureRecurringTodos(for month: Date) {
        guard !templates.isEmpty else { return }
        let active = templates.filter { $0.isActive }
        
        for t in active {
            let due = computeDue(for: t, in: month)
            
            if let idx = todos.firstIndex(where: { $0.templateId == t.id }) {
                todos[idx].due = due
                todos[idx].title = t.title
            } else {
                todos.append(CalendarTodo(title: t.title, done: false, due: due, templateId: t.id))
            }
            
            Task { await ReminderManager.scheduleMonthly(template: t, due: due, hour: 8) }
        }
        saveTodos()
    }
    
    // 31日→30/28日対応、0=月末
    private func computeDue(for tpl: RecurringTodoTemplate, in month: Date) -> Date {
        let start = cal.date(from: cal.dateComponents([.year,.month], from: month))!
        if tpl.dayOfMonth == 0 {
            // 月末
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
            return end
        } else {
            let range = cal.range(of: .day, in: .month, for: start)!
            let day = min(tpl.dayOfMonth, range.count)
            return cal.date(from: DateComponents(year: cal.component(.year, from: start),
                                                 month: cal.component(.month, from: start),
                                                 day: day)) ?? start
        }
    }
    private func handleQuickAdd(_ todo: CalendarTodo) {
        // テンプレ参照（@AppStorage decode は既に下部で定義済みの templates を使用）
        let tpl = templates.first { $0.id == todo.templateId }
        let catId = tpl?.defaultCategoryId ?? store.categories.first?.id
        let amount = tpl?.defaultAmount
        let memo = tpl?.defaultMemo
        let initialDate = todo.due ?? Date()
        
        sheet = .addPrefilled(
            date: initialDate,
            categoryId: catId,
            amount: amount,
            memo: memo
        )
    }

}

private struct TodoCard: View {
    let month: Date
    let todos: [CalendarTodo]
    let onToggle: (UUID) -> Void
    let onDelete: (IndexSet) -> Void
    let onEditDue: (UUID, Date?) -> Void
    @Binding var newTitle: String
    let onAdd: () -> Void
    @Binding var showOnlyUndone: Bool
    let onQuickAdd: (CalendarTodo) -> Void   // ← ここを必ず受け取る
    
    @Environment(\.colorScheme) private var scheme
    private var cal: Calendar { .current }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(monthTitle(month))のToDo", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Toggle(isOn: $showOnlyUndone) {
                    Text("未完のみ").font(.caption)
                }
                .toggleStyle(.switch)
                .labelsHidden()
            }
            
            // 追加バー
            HStack(spacing: 8) {
                TextField("新しいToDo（例：電気代の支払い）", text: $newTitle)
                    .textFieldStyle(.roundedBorder)
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .padding(8)
                        .background(Circle().fill(Color.accentColor.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            
            if todos.isEmpty {
                Text("この月のToDoはまだありません")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // ▼ “描画だけ”に徹して、アクションは外から注入
                List {
                    ForEach(todos) { t in
                        TodoRow(
                            month: month,
                            todo: t,
                            onToggle: onToggle,
                            onEditDue: onEditDue,
                            onQuickAdd: onQuickAdd
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: onDelete)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 260)
                .background(Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(scheme == .dark ? Color.white.opacity(0.06) : .white)
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.06), radius: 10, y: 5)
        )
    }
    
    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月"
        return f.string(from: date)
    }
}

private struct TodoRow: View {
    let month: Date
    let todo: CalendarTodo
    let onToggle: (UUID) -> Void
    let onEditDue: (UUID, Date?) -> Void
    let onQuickAdd: (CalendarTodo) -> Void
    
    @State private var showDuePicker = false
    @State private var tempDue: Date = Date()
    
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
                Text(todo.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(todo.done, pattern: .solid, color: .secondary)
                    .foregroundStyle(todo.done ? .secondary : .primary)
                
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.secondary)
                    
                    // 期日ラベル（期限超過は赤 / 当日は青ドットを追加）
                    HStack(spacing: 6) {
                        if let due = todo.due {
                            // 当日ドット
                            if cal.isDateInToday(due) {
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 6, height: 6)
                            }
                            Text(dueLabel(due))
                                .font(.caption)
                                .foregroundStyle(isOverdue(due) && !todo.done ? .red : .secondary)
                        } else {
                            Text("期日なし")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.thinMaterial))
                    .onTapGesture {
                        tempDue = todo.due ?? monthStart(month)
                        showDuePicker = true
                    }
                    .popover(isPresented: $showDuePicker, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                        DuePopover(
                            month: month,
                            tempDate: $tempDue,
                            onSave: { newDate in onEditDue(todo.id, newDate); showDuePicker = false },
                            onClear: { onEditDue(todo.id, nil); showDuePicker = false }
                        )
                        .presentationDetents([.medium])
                    }
                }
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .onTapGesture { onQuickAdd(todo) }
    }
    
    private func isOverdue(_ d: Date) -> Bool {
        let today = cal.startOfDay(for: Date())
        let due   = cal.startOfDay(for: d)
        return due < today
    }
    private func monthStart(_ date: Date) -> Date {
        let comps = cal.dateComponents([.year, .month], from: date)
        return cal.date(from: comps) ?? date
    }
    private func dueLabel(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = .init(identifier:"ja_JP"); f.dateFormat = "M/d(EEE)"
        return f.string(from: d)
    }
}

private struct DuePopover: View {
    let month: Date
    @Binding var tempDate: Date
    let onSave: (Date) -> Void
    let onClear: () -> Void
    
    private var cal: Calendar { .current }
    
    private var monthRange: ClosedRange<Date> {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        return start...end
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Text("期日を選択").font(.headline)
            DatePicker(
                "",
                selection: $tempDate,
                in: monthRange,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical) // ← 直感的で操作しやすい
            .labelsHidden()
            
            HStack {
                Button(role: .destructive) {
                    onClear()
                } label: {
                    Label("クリア", systemImage: "xmark.circle")
                }
                
                Spacer()
                
                Button {
                    onSave(tempDate)
                } label: {
                    Label("保存", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
    }
}
