//
//  Services/TodoStore.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import Foundation
import SwiftUI
import Combine

final class TodoStore: ObservableObject {
    @Published private(set) var todos: [CalendarTodo] = []
    private var cal: Calendar { .current }

    private let defaults: UserDefaults
    private let recurringTemplatesKey = "kakebo.recurring.templates"

    // Recurring（テンプレ）もここで管理（必要に応じて元の実装から移植）
    private var templates: [RecurringTodoTemplate] {
        guard let data = defaults.migratedData(forKey: recurringTemplatesKey) else { return [] }
        return (try? JSONDecoder().decode([RecurringTodoTemplate].self, from: data)) ?? []
    }

    init(userDefaults: UserDefaults? = .appGroup) {
        self.defaults = userDefaults ?? .standard
        self.defaults.migrateIfNeeded(keys: [recurringTemplatesKey])
    }

    // MARK: - Load / Save (month-scoped)
    private func key(for month: Date) -> String {
        let f = DateFormatter(); f.locale = .init(identifier:"ja_JP"); f.dateFormat = "yyyy-MM"
        return "kakebo.todos.\(f.string(from: month))"
    }

    func load(for month: Date) {
        let k = key(for: month)
        if let data = defaults.migratedData(forKey: k),
           let items = try? JSONDecoder().decode([CalendarTodo].self, from: data) {
            self.todos = items
        } else {
            self.todos = []
        }
        if shouldApplyRecurringTodos(for: month) {
            ensureRecurringTodos(for: month)
        }
        save(for: month) // normalize
    }

    func save(for month: Date) {
        let k = key(for: month)
        if let data = try? JSONEncoder().encode(todos) {
            defaults.set(data, forKey: k)
        }
    }
    
    // MARK: - Queries
    func todos(on day: Date) -> [CalendarTodo] {
        let start = cal.startOfDay(for: day)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        return todos.filter { t in
            guard let d = t.due else { return false }
            return d >= start && d < end
        }
    }
    
    func dueCounts(in month: Date) -> [Date: Int] {
        var dict: [Date: Int] = [:]
        let start = cal.date(from: cal.dateComponents([.year,.month], from: month))!
        let end   = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        
        for t in todos where t.done == false {
            if let d = t.due, d >= start && d <= end {
                let key = cal.startOfDay(for: d)
                dict[key, default: 0] += 1
            }
        }
        return dict
    }
    
    // MARK: - Mutations
    func add(title: String, due: Date?) {
        let t = CalendarTodo(title: title, done: false, due: due)
        todos.insert(t, at: 0)
    }
    
    func toggle(_ id: UUID) {
        guard let i = todos.firstIndex(where: {$0.id == id}) else { return }
        todos[i].done.toggle()
    }
    
    func setDue(_ id: UUID, _ due: Date?) {
        guard let i = todos.firstIndex(where: {$0.id == id}) else { return }
        todos[i].due = due
    }
    
    func rename(_ id: UUID, _ newTitle: String) {
        guard let i = todos.firstIndex(where: {$0.id == id}) else { return }
        todos[i].title = newTitle
    }
    
    func delete(ids: [UUID]) {
        todos.removeAll { ids.contains($0.id) }
    }
    
    // MARK: - Recurring templates
    private func shouldApplyRecurringTodos(for month: Date) -> Bool {
        let target = cal.date(from: cal.dateComponents([.year, .month], from: month))!
        let current = cal.date(from: cal.dateComponents([.year, .month], from: .now))!
        return target >= current
    }

    private func ensureRecurringTodos(for month: Date) {
        let active = templates.filter { $0.isActive }
        let activeIds = Set(active.map { $0.id })

        // 削除済み or 停止中のテンプレートに紐づくToDoを除去
        todos.removeAll { todo in
            guard let tid = todo.templateId else { return false }
            return !activeIds.contains(tid)
        }

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
    }
    
    // 31日→30/28日対応、0=月末
    private func computeDue(for tpl: RecurringTodoTemplate, in month: Date) -> Date {
        let start = cal.date(from: cal.dateComponents([.year,.month], from: month))!
        if tpl.dayOfMonth == 0 {
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
            return end
        } else {
            let range = cal.range(of: .day, in: .month, for: start)!
            let day = min(tpl.dayOfMonth, range.count)
            return cal.date(from: DateComponents(
                year: cal.component(.year, from: start),
                month: cal.component(.month, from: start),
                day: day
            )) ?? start
        }
    }
}
