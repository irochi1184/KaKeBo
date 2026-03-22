//
//  Settings/ReminderSettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI

struct ReminderSettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var todoStore: TodoStore
    @StateObject private var rstore = ReminderStore()
    @State private var editing: ReminderRule? = nil
    @State private var showEditor = false
    
    var body: some View {
        List {
            Section {
                if rstore.rules.isEmpty {
                    ContentUnavailableView(
                        "ルールがありません",
                        systemImage: "bell.slash",
                        description: Text("右上の＋から追加してください")
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(rstore.rules) { rule in
                        ReminderRuleRow(rule: rule,
                                        onToggle: { toggle in
                            var r = rule; r.enabled = toggle
                            rstore.update(r)
                            Task { await ReminderManagerV2.applyAll(rules: rstore.rules,
                                                                    store: store,
                                                                    todoStore: todoStore) }
                        },
                                        onTest: {
                            Task { await ReminderManagerV2.fireTest(rule: rule,
                                                                    store: store,
                                                                    todoStore: todoStore) }
                        })
                        .contentShape(Rectangle())
                        .onTapGesture {
                            editing = rule
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                rstore.delete([rule.id])
                                Task { await ReminderManagerV2.applyAll(rules: rstore.rules,
                                                                        store: store,
                                                                        todoStore: todoStore) }
                            } label: { Label("削除", systemImage: "trash") }
                        }
                    }
                    .onMove { from, to in
                        rstore.move(from: from, to: to)
                        Task { await ReminderManagerV2.applyAll(rules: rstore.rules,
                                                                store: store,
                                                                todoStore: todoStore) }
                    }
                }
            } header: {
                Text("通知ルール")
            } footer: {
                Text("曜日・条件・本文は各ルールごとに設定できます。")
            }
        }
        .navigationTitle("リマインダー")
        .listRowBackground(FlatListRowBackground())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton().disabled(rstore.rules.isEmpty) }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = ReminderRule(); showEditor = true
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing, onDismiss: {
            Task { await ReminderManagerV2.applyAll(rules: rstore.rules,
                                                    store: store,
                                                    todoStore: todoStore) }
        }) { rule in
            NavigationStack {
                ReminderRuleEditor(rule: rule,onSave: { result in
                    if let idx = rstore.rules.firstIndex(where: { $0.id == result.id }) {
                        rstore.rules[idx] = result
                    } else {
                        rstore.rules.append(result)
                    }
                    rstore.save()
                    editing = nil
                },
                                   previewTodosToday: todayTodosCount(),
                                   previewUnloggedToday: hasUnloggedToday()
                )
            }
            .presentationDetents([.large, .medium])
            .presentationDragIndicator(.visible)
        }
        .task {
            _ = await ReminderManager.requestAuthorization()
            await ReminderManagerV2.applyAll(rules: rstore.rules,
                                             store: store,
                                             todoStore: todoStore)
        }
    }
    
    private func todayTodosCount() -> Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return todoStore.todos.filter { $0.due.map { cal.isDate($0, inSameDayAs: today) } ?? false }
            .filter { !$0.done }
            .count
    }
    
    private func hasUnloggedToday() -> Bool {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return !store.transactions.contains { cal.isDate($0.date, inSameDayAs: today) }
    }
}

private struct ReminderRuleRow: View {
    let rule: ReminderRule
    let onToggle: (Bool) -> Void
    let onTest: () -> Void
    
    private var timeText: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; f.locale = .init(identifier: "ja_JP")
        return f.string(from: rule.time)
    }
    private var repeatText: String {
        switch rule.repeatType {
        case .daily: return "毎日 \(timeText)"
        case .weekly:
            let symbols = Calendar.current.shortStandaloneWeekdaySymbols // 日〜土
            let text = rule.weekdays.sorted().map { symbols[($0-1) % 7] }.joined()
            return "毎週 \(text) \(timeText)"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: rule.enabled ? "bell.badge" : "bell.slash")
                .foregroundStyle(rule.enabled ? Color.accentColor : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.title).font(.subheadline.weight(.medium))
                Text(repeatText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: .init(get: { rule.enabled }, set: onToggle))
                .labelsHidden()
            Button { onTest() } label: {
                Image(systemName: "paperplane").imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("テスト送信")
        }
    }
}
