//
//  Views/Calendar/CalendarScreen.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/23.
//

import SwiftUI
import UIKit

struct CalendarScreen: View {
    @Binding var showSideMenu: Bool
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var appRoute: AppRoute
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appVisualStyle) private var visualStyle
    public var cal: Calendar { .current }
    @StateObject private var keyboard = KeyboardHeightReader()
    @StateObject private var dayNotes = DayNotesStore()

    @State private var month: Date = Calendar.current.date(from:Calendar.current.dateComponents([.year,.month], from: .now)
    ) ?? .now
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
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @AppStorage("calendar.bottom.display.mode", store: .appGroup) private var calendarBottomMode: CalendarBottomDisplayMode = .monthTodo
    
    var body: some View {
        let accent = themeStore.theme.accentColor(for: scheme)
        
        // どこでも横にスワイプしたら月移動（縦優勢は無視）
        let swipeGesture = DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > abs(dy), abs(dx) > 40 else { return } // 横優勢 & 十分な距離
                if dx < 0 { nextMonth() } else { previousMonth() }
            }
        NavigationStack {
            VStack(spacing: 12) {
                Group {
                    if keyboard.height == 0 {
                        // 曜日ヘッダー
                        VStack(spacing: 8) {
                            // 曜日ヘッダー
                            HStack {
                                // shortStandaloneWeekdaySymbols は 0:日〜6:土 の順
                                ForEach(Array(weekdaySymbolsJP.enumerated()), id: \.offset) { index, w in
                                    Text(w)
                                        .font(.caption)
                                        .foregroundStyle(weekdayHeaderColor(index: index))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .padding(.horizontal, 8)
                            .transition(.move(edge: .top).combined(with: .opacity))
                            
                            // 月グリッド
                            CalendarMonthGrid(
                                month: month,
                                expenseBuckets: expenseBuckets,
                                incomeBuckets: incomeBuckets,
                                maxExpense: maxExpenseInMonth,
                                maxIncome: maxIncomeInMonth,
                                todoCounts: todoStore.dueCounts(in: month),
                                accent: accent,
                                selectedDate: calendarBottomMode == .dayDetail ? selectedDay : nil,
                                onTapDay: { day in
                                    if calendarBottomMode == .dayDetail {
                                        selectedDay = day
                                    } else {
                                        sheet = .detail(day)
                                    }
                                },
                                onLongPressDay: { day in sheet = .add(day) },
                                notedDays: dayNotes.notedDays(in: month),
                                noteSnippets: dayNotes.snippets(in: month, limit: 8)
                            )
                            .padding(.horizontal)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        // ここがポイント：この塊にだけスワイプを付与
                        .contentShape(Rectangle()) // 余白でもドラッグを拾えるように
                        .simultaneousGesture(swipeGesture, including: .all)
                    }
                }

                Divider()
                    .padding(.horizontal)
                
                Group {
                    switch calendarBottomMode {
                    case .monthTodo:
                        TodoListCard(
                            month: month,
                            todos: showOnlyUndone ? todoStore.todos.filter { !$0.done } : todoStore.todos,
                            accent: accent,
                            onToggle: { id in todoStore.toggle(id); todoStore.save(for: month) },
                            onDelete: { offsets in
                                let base = showOnlyUndone ? todoStore.todos.filter { !$0.done } : todoStore.todos
                                let ids = offsets.map { base[$0].id }
                                todoStore.delete(ids: ids)
                                todoStore.save(for: month)
                            },
                            onEditDue: { id, newDate in todoStore.setDue(id, newDate); todoStore.save(for: month) },
                            onQuickAdd: { tapped in handleQuickAdd(tapped) },
                            onRename: { id, newTitle in todoStore.rename(id, newTitle); todoStore.save(for: month) },
                            onTapAdd: { sheet = .todoAdd },
                            showOnlyUndone: $showOnlyUndone
                        )
                        .environmentObject(todoStore)

                    case .dayDetail:
                        CalendarDayDetailCard(
                            date: selectedDay,
                            accent: accent
                        )
                        .environmentObject(todoStore)
                        .environmentObject(dayNotes)
                    }
                }
                .id(calendarBottomMode)
                .frame(maxHeight: calendarBottomMode == .dayDetail ? .infinity : nil)
                .padding(.horizontal)
                
                Spacer(minLength: calendarBottomMode == .dayDetail ? 0 : 8)
            }
            .background(
                themeStore.theme.backgroundColor(for: scheme).ignoresSafeArea()
            )
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
                ToolbarItem(placement: .principal) {
                    YearMonthHeader(
                        month: $month,
                        title: title(month),
                        accent: accent
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .add(.now)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent.opacity(0.2))
                    .accessibilityLabel("新規追加")
                }
            }
            .sheet(item: $sheet) { s in
                switch s {
                case .detail(let date):
                    DayDetailSheet(date: date, accent: accent)
                        .environmentObject(store)
                        .environmentObject(todoStore)
                        .environmentObject(themeStore)
                        .environmentObject(dayNotes)
                    
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
                        accent: accent,
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
            .onAppear {
                todoStore.load(for: month)
                if calendarBottomMode == .dayDetail {
                    selectedDay = cal.startOfDay(for: .now)
                }
                applyIncomingCalendarSelection()
            }
            .onChange(of: month) { _, newMonth in
                todoStore.load(for: newMonth)
                if calendarBottomMode == .dayDetail, !cal.isDate(selectedDay, equalTo: newMonth, toGranularity: .month) {
                    selectedDay = cal.date(from: cal.dateComponents([.year, .month], from: newMonth)) ?? newMonth
                }
            }
            .onChange(of: calendarBottomMode) {
                if calendarBottomMode == .dayDetail {
                    selectedDay = cal.startOfDay(for: .now)
                }
            }
            .task { await reloadSharedLedgerDataIfNeeded() }
            .task(id: ledgerContext.isShared) {
                await reloadSharedLedgerDataIfNeeded()
            }
            .task(id: ledgerContext.selectedSharedLedgerId) {
                await reloadSharedLedgerDataIfNeeded()
            }
            .onChange(of: appRoute.calendarSelection) { _, _ in
                applyIncomingCalendarSelection()
            }
        }
        .safeAreaInset(edge: .bottom) {
            // キーボードの重なり分だけ下に “空き” を作る
            Color.clear
                .frame(height: max(0, keyboard.height))
                .animation(.snappy, value: keyboard.height)
        }
    }
    
    // MARK: - 集計
    private var personalTransactionsThisMonth: [Transaction] {
        store.transactions.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private var sharedTransactionsThisMonth: [SharedTransaction] {
        guard
            ledgerContext.isShared,
            let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore)
        else { return [] }

        let all = sharedLedgerStore.transactionsByLedger[ledger.id] ?? []
        return all.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    /// 日別 “支出” 合計
    private var expenseBuckets: [Date: Int] {
        if ledgerContext.isShared {
            var dict: [Date: Int] = [:]
            for tx in sharedTransactionsThisMonth where tx.type == .expense {
                let key = cal.startOfDay(for: tx.date)
                dict[key, default: 0] += tx.amount
            }
            return dict
        } else {
            var dict: [Date: Int] = [:]
            for tx in personalTransactionsThisMonth where tx.type == .expense {
                let key = cal.startOfDay(for: tx.date)
                dict[key, default: 0] += tx.amount
            }
            return dict
        }
    }

    /// 日別 “収入” 合計
    private var incomeBuckets: [Date: Int] {
        if ledgerContext.isShared {
            var dict: [Date: Int] = [:]
            for tx in sharedTransactionsThisMonth where tx.type == .income {
                let key = cal.startOfDay(for: tx.date)
                dict[key, default: 0] += tx.amount
            }
            return dict
        } else {
            var dict: [Date: Int] = [:]
            for tx in personalTransactionsThisMonth where tx.type == .income {
                let key = cal.startOfDay(for: tx.date)
                dict[key, default: 0] += tx.amount
            }
            return dict
        }
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

    /// 曜日ヘッダーの色: 日曜=赤 / 土曜=青 / 平日=グレー
    private func weekdayHeaderColor(index: Int) -> Color {
        switch index {
        case 0: return .red
        case 6: return .blue
        default: return Color(.secondaryLabel)
        }
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

    private func reloadSharedLedgerDataIfNeeded() async {
        guard ledgerContext.isShared,
              let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore) else { return }

        await sharedLedgerStore.reloadCategories(for: ledger)
        await sharedLedgerStore.reloadTransactions(for: ledger)
    }

    private func applyIncomingCalendarSelection() {
        guard let date = appRoute.consumeCalendarSelection() else { return }
        let start = cal.startOfDay(for: date)
        month = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
        selectedDay = start
        calendarBottomMode = .dayDetail
    }

}

// CalendarScreen.swift の末尾などに追加
private struct TodoListCard: View {
    let month: Date
    let todos: [CalendarTodo]
    let accent: Color
    let onToggle: (UUID) -> Void
    let onDelete: (IndexSet) -> Void
    let onEditDue: (UUID, Date?) -> Void
    let onQuickAdd: (CalendarTodo) -> Void
    let onRename: (UUID, String) -> Void
    let onTapAdd: () -> Void
    @Binding var showOnlyUndone: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.appVisualStyle) private var visualStyle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(monthTitle(month))のToDo", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Toggle(isOn: $showOnlyUndone) { Text("未完のみ").font(.caption) }
                    .tint(accent)
                    .toggleStyle(.switch)
                    .labelsHidden()
                Button {
                    onTapAdd()
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
                .accessibilityLabel("新規追加")
                .hoverEffect(.highlight)
                .buttonStyle(.plain)
                .accessibilityLabel("ToDoを追加")
            }
            
            if todos.isEmpty {
                Text("この月のToDoはまだありません")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                // 並び替え：期日なしが先頭、その後は期日が新しい順（降順）
                let sortedTodos = todos.sorted {
                    switch ($0.due, $1.due) {
                    case (nil, nil):
                        return false // どちらもなし → 元の順
                    case (nil, _):
                        return true  // 左がなし → 左を前に
                    case (_, nil):
                        return false // 右がなし → 右を後ろに
                    case let (d1?, d2?):
                        return d1 > d2 // 両方ある → 新しい順（降順）
                    }
                }
                
                List {
                    ForEach(sortedTodos) { t in
                        TodoRow(
                            month: month,
                            todo: t,
                            accent: accent,
                            onToggle: onToggle,
                            onEditDue: onEditDue,
                            onQuickAdd: onQuickAdd,
                            onRename: onRename
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        // 1) 元配列 todos の id→index マップを作る
                        let indexMap: [UUID: Int] = Dictionary(
                            uniqueKeysWithValues: todos.enumerated().map { ($0.element.id, $0.offset) }
                        )
                        // 2) 表示中(sorted)のインデックス → 元配列インデックスへ変換
                        let original = IndexSet(
                            offsets.compactMap { idx in
                                indexMap[sortedTodos[idx].id]
                            }
                        )
                        // 3) 既存の onDelete(IndexSet) を元配列のインデックスで呼ぶ
                        onDelete(original)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 260)
                .background(FlatCardBackground(cornerRadius: 16))
            }
        }
        .flatCard(cornerRadius: 16, padding: 12)
    }
    
    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = .init(identifier: "ja_JP"); f.dateFormat = "M月"
        return f.string(from: date)
    }
}

private struct TodoRow: View {
    let month: Date
    let todo: CalendarTodo
    let accent: Color
    let onToggle: (UUID) -> Void
    let onEditDue: (UUID, Date?) -> Void
    let onQuickAdd: (CalendarTodo) -> Void
    let onRename: (UUID, String) -> Void
    
    @State private var showDuePicker = false
    @State private var tempDue: Date = Date()
    
    @State private var isRenaming = false
    @State private var tempTitle: String = ""
    @FocusState private var titleFocused: Bool
    
    private var cal: Calendar { .current }
    
    var body: some View {
        HStack(spacing: 10) {
            Button { onToggle(todo.id) } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            
            VStack(alignment: .leading, spacing: 4) {
                
                // ▼ タイトル（タップで編集）
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
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .onAppear {
                        tempTitle = todo.title
                        titleFocused = true
                    }
                } else {
                    Text(todo.title)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(todo.done, pattern: .solid, color: .secondary)
                        .foregroundStyle(todo.done ? .secondary : .primary)
                        .onTapGesture {    // ← タイトルをタップで編集開始
                            isRenaming = true
                        }
                }
                
                // ▼ 期日バッジ
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 6) {
                        if let due = todo.due {
                            if cal.isDateInToday(due) {
                                Circle().fill(Color.blue).frame(width: 6, height: 6)
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
                            accent: accent,
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
        .onTapGesture { onQuickAdd(todo) } // 行全体タップは従来どおりQuickAdd（タイトル部分は上書きされない）
    }
    
    private func commitRename() {
        let t = tempTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty, t != todo.title {
            onRename(todo.id, t)
        }
        isRenaming = false
        titleFocused = false
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
    let accent: Color
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
                        .foregroundStyle(.red)
                }
                
                Spacer()
                
                Button {
                    onSave(tempDate)
                } label: {
                    Label("保存", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .tint(accent)
        .padding(16)
    }
}

// 追加ビュー
private struct TodoAddSheet: View {
    let accent: Color
    let onAdd: (String, Date?) -> Void
    let defaultMonth: Date
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var withDue: Bool = true
    @State private var due: Date
    
    private var cal: Calendar { .current }
    
    init(accent: Color,onAdd: @escaping (String, Date?) -> Void, defaultMonth: Date) {
        self.accent = accent
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
                        .tint(accent)
                    if withDue {
                        DatePicker(
                            "期日",
                            selection: $due,
                            in: monthRange,
                            displayedComponents: .date
                        )
                        .tint(accent)
                    }
                }
            }
            .navigationTitle("ToDoを追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    let canAdd = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    BarPrimaryButton(title: "追加", isEnabled: canAdd, accent: accent) {
                        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        onAdd(t, withDue ? due : nil)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(350)])
    }
}

struct BarPrimaryButton: View {
    let title: String
    let isEnabled: Bool
    let accent: Color
    let action: () -> Void
    
    var body: some View {
        if isEnabled {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .tint(accent)
        } else {
            Button(title, action: {})
                .buttonStyle(.bordered)
                .disabled(true) // ← 見た目も無効化
        }
    }
}

private extension CalendarScreen {
    func previousMonth() {
        if let newMonth = cal.date(byAdding: .month, value: -1, to: month) {
            withAnimation(.snappy) { month = newMonth }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
    func nextMonth() {
        if let newMonth = cal.date(byAdding: .month, value: 1, to: month) {
            withAnimation(.snappy) { month = newMonth }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
