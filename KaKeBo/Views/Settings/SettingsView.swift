//
//  Views/Settings/SettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/22.
//

import SwiftUI
import UserNotifications
import UIKit

struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    
    @AppStorage("reminder.enabled") private var enabled: Bool = true
    @AppStorage("reminder.time") private var timeRaw: Double = defaultTime.timeIntervalSinceReferenceDate
    // ▼ リマインダー統一：Settings 内で共有する ToDo ストア（今日の件数評価などに使う）
    @StateObject private var todoStore = TodoStore()
    
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: Sheet?
    
    @AppStorage("kakebo.recurring.templates") private var templatesData: Data = Data()
    @State private var templates: [RecurringTodoTemplate] = []
    @State private var showNotifAlert = false
    @State private var notifMessage: String = "現在通知の許可設定ができていません。iOSの「設定」アプリから通知を許可してください。"
    
    enum Sheet: Identifiable {
        case reminders, categories, recurringTodos, fixedExpenses, theme
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
        let accent = themeStore.theme.accentColor(for: scheme)
        NavigationStack {
            Form {
                Section { // ← 1セクションにまとめる
                    // リマインダー
                    SettingsRowButton(
                        title: "リマインダーを管理",
                        systemImage: "bell.badge",
                        accent: accent,
                        trailingText: reminderCountText
                    ) {
                        Task {
                            if await hasNotificationPermission() {
                                sheet = .reminders
                            } else {
                                notifMessage = "現在通知の許可設定ができていません。iOSの「設定」アプリ > 通知 > KaKeBo からオンにしてください。"
                                showNotifAlert = true
                            }
                        }
                    }
                    
                    // カテゴリ
                    SettingsRowButton(
                        title: "カテゴリを管理",
                        systemImage: "square.grid.2x2",
                        accent: accent,
                        trailingText: "\(store.categories.count)件"
                    ) {
                        sheet = .categories
                    }
                    
                    // 毎月のToDo
                    SettingsRowButton(
                        title: "毎月のToDoを管理",
                        systemImage: "calendar.badge.clock",
                        accent: accent,
                        trailingText: "\(recurringCount)件"
                    ) {
                        sheet = .recurringTodos
                    }
                    
                    // 固定費
                    SettingsRowButton(
                        title: "固定費を管理",
                        systemImage: "yensign.circle",
                        accent: accent,
                        trailingText: fixedCountText
                    ) {
                        sheet = .fixedExpenses
                    }
                    
                    // テーマ
                    SettingsRowButton(
                        title: "テーマ管理",
                        systemImage: "paintpalette",
                        accent: accent,
                        trailingText: nil
                    ) {
                        sheet = .theme
                    }
                } header: {
                    Text("各種設定")
                }
            }
            .scrollContentBackground(.hidden) // デフォルトのグレー背景を非表示
            .background(
                themeStore.theme.backgroundColor(for: scheme) // テーマの背景色
                    .ignoresSafeArea()
            )
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
                    
                case .theme:
                    NavigationStack {
                        ThemeSettingsView()
                            .navigationTitle("テーマ管理")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)

                }
            }
            .background(themeStore.theme.backgroundColor(for: scheme))
        }
        .alert("通知が許可されていません", isPresented: $showNotifAlert) {
            Button("設定を開く") { openAppSettings() }
            Button("閉じる", role: .cancel) { }
        } message: {
            Text(notifMessage)
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
    
    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    /// 現在の通知権限を“問い合わせのみ”で確認（プロンプトは出さない）
    private func hasNotificationPermission() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            UNUserNotificationCenter.current().getNotificationSettings { s in
                let ok: Bool = {
                    switch s.authorizationStatus {
                    case .authorized, .provisional, .ephemeral: return true
                    default: return false
                    }
                }()
                cont.resume(returning: ok)
            }
        }
    }
    
}

private struct SettingsRowButton: View {
    let title: String
    let systemImage: String
    let accent: Color
    let trailingText: String?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                // 左アイコン＋タイトル
                Label {
                    Text(title) // テキストはデフォルトカラー
                } icon: {
                    Image(systemName: systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                }
                
                Spacer()
                
                // 右側の補足テキスト
                if let trailingText {
                    Text(trailingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // 「>」アイコン（右矢印）
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle()) // ← 行全体をタップ領域に
        }
        .buttonStyle(.plain) // デフォルトの青ハイライト無効
    }
}
