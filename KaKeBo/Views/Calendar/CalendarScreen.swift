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
    
    // CalendarScreen 内（struct の先頭付近）にある enum Sheet を“この形”に置き換え
    enum Sheet: Identifiable, Equatable {
        case detail(Date)
        case add(Date)
        case addPrefilled(date: Date, categoryId: UUID?, amount: Int?, memo: String?)
        case todoAdd
        
        var id: String {
            switch self {
            case .detail(let d):         return "detail-\(d.timeIntervalSince1970)"
            case .add(let d):            return "add-\(d.timeIntervalSince1970)"
            case .addPrefilled(let d, _, _, _):
                return "addp-\(d.timeIntervalSince1970)"
            case .todoAdd:               return "todoAdd"
            }
        }
    }

    @StateObject private var todoStore = TodoStore()
    @State private var showOnlyUndone: Bool = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
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
                    todoCounts: todoStore.dueCounts(in: month),
                    onTapDay: { day in
                        sheet = .detail(day)
                    },
                    onLongPressDay: { day in
                        sheet = .add(day)
                    }
                )
                .padding(.horizontal)
                
                TodoListCard(
                    month: month,
                    todos: showOnlyUndone ? todoStore.todos.filter{ !$0.done } : todoStore.todos,
                    onToggle: { id in todoStore.toggle(id); todoStore.save(for: month) },
                    onDelete: { offsets in
                        let base = showOnlyUndone ? todoStore.todos.filter{ !$0.done } : todoStore.todos
                        let ids = offsets.map { base[$0].id }
                        todoStore.delete(ids: ids)
                        todoStore.save(for: month)
                    },
                    onEditDue: { id, newDate in todoStore.setDue(id, newDate); todoStore.save(for: month) },
                    onQuickAdd: { tapped in handleQuickAdd(tapped) }, // 既存のまま
                    onTapAdd: { sheet = .todoAdd },
                    showOnlyUndone: $showOnlyUndone
                )
                .environmentObject(todoStore)
                .padding(.horizontal)
                
                Spacer(minLength: 8)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    YearMonthHeader(
                        month: $month,
                        title: title(month)  // "yyyy年M月"
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                }
                
                // 右上の「支出追加」ボタンはそのまま
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .add(.now)
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $sheet) { s in
                switch s {
                case .detail(let date):
                    DayDetailSheet(date: date)
                        .environmentObject(store)
                        .environmentObject(todoStore)
                    
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
                case .todoAdd:
                    TodoAddSheet(
                        onAdd: { title, due in
                            let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !t.isEmpty else { return }
                            todoStore.add(title: t, due: due)
                            todoStore.save(for: month)
                        },
                        defaultMonth: month
                    )
                }
            }
            .onAppear { todoStore.load(for: month) }
            .onChange(of: month) { todoStore.load(for: month) }
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
    
    @AppStorage("kakebo.recurring.templates") private var templatesData: Data = Data()
    private var templates: [RecurringTodoTemplate] {
        (try? JSONDecoder().decode([RecurringTodoTemplate].self, from: templatesData)) ?? []
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

// CalendarScreen.swift の末尾などに追加
private struct TodoListCard: View {
    let month: Date
    let todos: [CalendarTodo]
    let onToggle: (UUID) -> Void
    let onDelete: (IndexSet) -> Void
    let onEditDue: (UUID, Date?) -> Void
    let onQuickAdd: (CalendarTodo) -> Void
    let onTapAdd: () -> Void
    @Binding var showOnlyUndone: Bool
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(monthTitle(month))のToDo", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Toggle(isOn: $showOnlyUndone) { Text("未完のみ").font(.caption) }
                    .toggleStyle(.switch)
                    .labelsHidden()
                Button {
                    onTapAdd()
                } label: {
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle().stroke(.white.opacity(0.25), lineWidth: 0.8)
                            )
                            .shadow(color: .black.opacity(0.1), radius: 3, y: 2)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新規追加")
                .hoverEffect(.highlight) // iPadなどで反応あり
                .buttonStyle(.plain)
                .accessibilityLabel("ToDoを追加")
            }
            
            if todos.isEmpty {
                Text("この月のToDoはまだありません")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
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
        let f = DateFormatter(); f.locale = .init(identifier: "ja_JP"); f.dateFormat = "M月"
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

struct DuePopover: View {
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

// 追加ビュー
private struct TodoAddSheet: View {
    let onAdd: (String, Date?) -> Void
    let defaultMonth: Date
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var withDue: Bool = true
    @State private var due: Date
    
    private var cal: Calendar { .current }
    
    init(onAdd: @escaping (String, Date?) -> Void, defaultMonth: Date) {
        self.onAdd = onAdd
        self.defaultMonth = defaultMonth
        // 月初を初期日付に
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year,.month], from: defaultMonth))!
        _due = State(initialValue: start)
    }
    
    private var monthRange: ClosedRange<Date> {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: defaultMonth))!
        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        return start...end
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("タイトル（例：電気代の支払い）", text: $title)
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Toggle("期日を設定", isOn: $withDue)
                    if withDue {
                        DatePicker(
                            "期日",
                            selection: $due,
                            in: monthRange,
                            displayedComponents: .date
                        )
                    }
                }
            }
            .navigationTitle("ToDoを追加")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("追加") {
                        onAdd(title, withDue ? due : nil)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

