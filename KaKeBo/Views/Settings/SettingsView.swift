//
//  Views/Settings/SettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/22.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    
    @AppStorage("reminder.enabled") private var enabled: Bool = true
    @AppStorage("reminder.time") private var timeRaw: Double = defaultTime.timeIntervalSinceReferenceDate
    // ▼ リマインダー統一：Settings 内で共有する ToDo ストア（今日の件数評価などに使う）
    @StateObject private var todoStore = TodoStore()
    
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: Sheet?
    
    @AppStorage("kakebo.recurring.templates") private var templatesData: Data = Data()
    @State private var templates: [RecurringTodoTemplate] = []
    
    enum Sheet: Identifiable {
        case reminders
        case categories
        case recurringTodos
        case fixedExpenses
        var id: String { "sheet-\(self)" }
    }
    
    private static var defaultTime: Date {
        var comps = DateComponents()
        comps.hour = 21; comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
    
    private var selectedTime: Date {
        get { Date(timeIntervalSinceReferenceDate: timeRaw) }
        set { timeRaw = newValue.timeIntervalSinceReferenceDate }
    }
    
    private func loadTemplates() {
        if templatesData.isEmpty { templates = []; return }
        if let items = try? JSONDecoder().decode([RecurringTodoTemplate].self, from: templatesData) {
            templates = items
        }
    }
    private func saveTemplates() {
        templatesData = (try? JSONEncoder().encode(templates)) ?? Data()
    }
    private var recurringCount: Int {
        (try? JSONDecoder().decode([RecurringTodoTemplate].self, from: templatesData))?.count ?? 0
    }
    private var fixedCountText: String {
        let data = UserDefaults.standard.data(forKey: DataStore.fixedTemplatesKey) ?? Data()
        let count = (try? JSONDecoder().decode([FixedExpenseTemplate].self, from: data))?.count ?? 0
        return "\(count)件"
    }
    private var reminderCountText: String {
        let data = UserDefaults.standard.data(forKey: ReminderStore.storageKey) ?? Data()
        let rules = (try? JSONDecoder().decode([ReminderRule].self, from: data)) ?? []
        let enabled = rules.filter { $0.enabled }.count
        return "有効 \(enabled)/\(rules.count) 件"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // リマインダー（他と同じボタン→シート方式に統一）
                Section("リマインダー") {
                    Button {
                        sheet = .reminders
                    } label: {
                        HStack {
                            Label("リマインダーを管理", systemImage: "bell.badge")
                            Spacer()
                            Text(reminderCountText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("カテゴリ") {
                    Button {
                        sheet = .categories
                    } label: {
                        HStack {
                            Label("カテゴリを管理", systemImage: "square.grid.2x2")
                            Spacer()
                            Text("\(store.categories.count)件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("毎月のToDo") {
                    Button {
                        sheet = .recurringTodos
                    } label: {
                        HStack {
                            Label("毎月のToDoを管理", systemImage: "calendar.badge.clock")
                            Spacer()
                            Text("\(recurringCount)件")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("固定費（毎月の定額支出）") {
                    Button {
                        sheet = .fixedExpenses
                    } label: {
                        HStack {
                            Label("固定費を管理", systemImage: "yensign.circle")
                            Spacer()
                            Text(fixedCountText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .onAppear {
                loadTemplates()
                // 今日の月データだけロード（通知の条件評価で使用）
                let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))!
                todoStore.load(for: monthStart)
            }
            .onChange(of: templates) { _, _ in saveTemplates() }
            .sheet(item: $sheet) { s in
                switch s {
                case .reminders:
                    NavigationStack {
                        ReminderSettingsView()
                            .environmentObject(store)
                            .environmentObject(todoStore)
                            .navigationTitle("リマインダー")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
                    
                case .categories:
                    NavigationStack {
                        CategoryListView()
                            .environmentObject(store)
                            .navigationTitle("カテゴリ")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
                    
                case .recurringTodos:
                    NavigationStack {
                        RecurringTodoSettingsView()
                            .navigationTitle("毎月のToDo")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
                    
                case .fixedExpenses:
                    NavigationStack {
                        FixedExpenseSettingsView()
                            .environmentObject(store)
                            .navigationTitle("固定費")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
                }
            }
        }
    }
    
    private func applyScheduling() async {
        if enabled {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
            await ReminderManager.scheduleDaily(hour: comps.hour ?? 21, minute: comps.minute ?? 0)
        } else {
            await ReminderManager.cancel(id: ReminderManager.dailyId)
        }
    }
    
}
