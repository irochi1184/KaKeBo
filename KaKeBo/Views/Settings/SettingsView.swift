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
    
    @Environment(\.dismiss) private var dismiss
    @State private var notifAuthorized = false
    @State private var sheet: Sheet?
    
    @AppStorage("kakebo.recurring.templates") private var templatesData: Data = Data()
    @State private var templates: [RecurringTodoTemplate] = []
    @State private var newTitle: String = ""
    @State private var newDay: Int = 0 // 0=月末, 1...31
    
    enum Sheet: Identifiable {
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
    
    var body: some View {
        NavigationStack {
            Form {
                Section("リマインダー") {
                    Toggle("毎日通知する", isOn: $enabled)
                        .onChange(of: enabled) { _, _ in
                            Task { await applyScheduling() }
                        }
                    
                    DatePicker(
                        "時刻",
                        selection: .init(
                            get: { selectedTime },
                            set: { newVal in
                                timeRaw = newVal.timeIntervalSinceReferenceDate
                                Task { await applyScheduling() }
                            }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .disabled(!enabled)
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
                                .font(.caption).foregroundStyle(.secondary)
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
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("設定")
            .onAppear {
                loadTemplates()
            }
            .onChange(of: templates) { _, _ in saveTemplates() }
            .task {
                notifAuthorized = await ReminderManager.requestAuthorization()
                if enabled { await applyScheduling() }
            }
            .sheet(item: $sheet) { s in
                switch s {
                case .categories:
                    // カテゴリ画面を “中で” NavigationStack 付きで出すと安定
                    NavigationStack {
                        CategoryListView()
                            .environmentObject(store)
                            .navigationTitle("カテゴリ")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    // iPad/Macでも確実に画面っぽく出るように
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
                        FixedExpenseSettingsView()          // ← 新規（次章）
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
    
    private var fixedCountText: String {
        let data = UserDefaults.standard.data(forKey: DataStore.fixedTemplatesKey) ?? Data()
        let count = (try? JSONDecoder().decode([FixedExpenseTemplate].self, from: data))?.count ?? 0
        return "\(count)件"
    }

}
