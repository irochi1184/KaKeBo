//
//  Views/Settings/SettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/22.
//

import SwiftUI
import UserNotifications
import UIKit
import UniformTypeIdentifiers

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
    @State private var showPaywall = false
    @State private var showShareSheet = false
    // バックアップ作成／復元
    @State private var showImporter = false
    @State private var exportDoc: KaKeBoBackupDocument? = nil
    @State private var showingExporter = false
    @State private var importReportText: String? = nil
    @State private var showImportDone = false
    
    struct KaKeBoBackupDocument: FileDocument {
        static var readableContentTypes: [UTType] = [.kakeboBackup, .json]
        static var writableContentTypes: [UTType] = [.kakeboBackup, .json]
        
        var data: Data
        init(data: Data) { self.data = data }
        init(configuration: ReadConfiguration) throws {
            guard let d = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
            self.data = d
        }
        func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
            FileWrapper(regularFileWithContents: data)
        }
    }
    
    enum Sheet: Identifiable {
        case reminders, categories, recurringTodos, fixedExpenses, theme, help
        var id: String { "sheet-\(self)" }
    }
    // 外部URL
    private let appleWidgetURL = URL(string: "https://support.apple.com/ja-jp/HT207122")!
    // KaKeBoの App Store URL
    private let appStoreURL = URL(string: "https://apps.apple.com/app/id6754249349")!
    
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
            VStack(spacing: 0) {
                PremiumBanner(accent: accent) {
                    showPaywall = true
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(themeStore.theme.backgroundColor(for: scheme).opacity(0.7))
                
                Form {
                    settingsSection(accent: accent)
                    supportSection(accent: accent)
                }
                .scrollContentBackground(.hidden)
                .onAppear {
                    loadTemplates()
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
                        
                    case .help:
                        NavigationStack {
                            HelpFAQView()
                                .navigationTitle("使い方・よくある質問")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)
                    }
                }
                .sheet(isPresented: $showShareSheet) {
                    ActivityView(activityItems: [appStoreURL])
                        .presentationDetents([.medium])
                }
                .sheet(isPresented: $showPaywall) {
                    PremiumPaywallView(accent: accent)
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)
                }
                .background(themeStore.theme.backgroundColor(for: scheme))
            }
        }
        .alert("通知が許可されていません", isPresented: $showNotifAlert) {
            Button("設定を開く") { openAppSettings() }
            Button("閉じる", role: .cancel) { }
        } message: {
            Text(notifMessage)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDoc,
            contentType: .kakeboBackup,
            defaultFilename: "KaKeBo_backup_\(Self.todayString()).kakebo"
        ) { result in
            if case .success = result {
                // 成功時の任意トーストなど
                print("バックアップ保存完了")
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.kakeboBackup, .json, .commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    importReportText = "ファイルが選択されませんでした"
                    showImportDone = true
                    return
                }
                handleImportedURL(url)   // ← 下の修正版に差し替え
            case .failure(let error):
                importReportText = "ファイル選択に失敗: \(error.localizedDescription)"
                showImportDone = true
            }
        }
        .alert("バックアップ復元", isPresented: $showImportDone) {   // ← アラートをビューに戻す
            Button("OK", role: .cancel) { }
        } message: {
            Text(importReportText ?? "")
        }
    }
    
    private func handleImportedURL(_ url: URL) {
        let needsSecurity = url.startAccessingSecurityScopedResource()
        defer { if needsSecurity { url.stopAccessingSecurityScopedResource() } }
        
        do {
            let data = try Data(contentsOf: url)
            
            Task(priority: .userInitiated) {
                do {
                    // まずバックグラウンドで JSON/CSV を軽くバリデーションしておきたい場合はここでやる
                    
                    // DataStore の変更は必ず MainActor で
                    let report = try await MainActor.run { () -> DataStore.ImportReport in
                        try store.importBackup(data: data) { restoredTheme in
                            // Theme の反映も MainActor
                            themeStore.theme = restoredTheme
                        }
                    }
                    
                    await MainActor.run {
                        importReportText = "復元完了：取込 \(report.inserted) 件 / 新規カテゴリ \(report.createdCategories) 件 / スキップ \(report.skipped) 件"
                        showImportDone = true
                    }
                } catch {
                    await MainActor.run {
                        importReportText = "復元に失敗: \(error.localizedDescription)"
                        showImportDone = true
                    }
                }
            }
        } catch {
            importReportText = "ファイル読み込みに失敗: \(error.localizedDescription)"
            showImportDone = true
        }
    }

    // MARK: - Sections split (to help type-checker)
    
    @ViewBuilder
    private func settingsSection(accent: Color) -> some View {
        Section {
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
            
            SettingsRowButton(
                title: "カテゴリを管理",
                systemImage: "square.grid.2x2",
                accent: accent,
                trailingText: "\(store.categories.count)件"
            ) { sheet = .categories }
            
            SettingsRowButton(
                title: "毎月のToDoを管理",
                systemImage: "calendar.badge.clock",
                accent: accent,
                trailingText: "\(recurringCount)件"
            ) { sheet = .recurringTodos }
            
            SettingsRowButton(
                title: "固定費を管理",
                systemImage: "yensign.circle",
                accent: accent,
                trailingText: fixedCountText
            ) { sheet = .fixedExpenses }
            
            SettingsRowButton(
                title: "テーマ管理",
                systemImage: "paintpalette",
                accent: accent,
                trailingText: nil
            ) { sheet = .theme }
        } header: {
            Text("各種設定")
        }
        .listRowBackground(scheme == .dark ? Color.white.opacity(0.06) : .white)
    }
    
    @ViewBuilder
    private func supportSection(accent: Color) -> some View {
        Section {
            SettingsRowButton(
                title: "使い方・よくある質問",
                systemImage: "questionmark.circle",
                accent: accent,
                trailingText: nil
            ) { sheet = .help }
            
            SettingsRowButton(
                title: "ウィジェットの使い方",
                systemImage: "apps.iphone",
                accent: accent,
                trailingText: "Apple公式"
            ) { UIApplication.shared.open(appleWidgetURL) }
            
            SettingsRowButton(
                title: "友達にKaKeBoを共有する",
                systemImage: "square.and.arrow.up",
                accent: accent,
                trailingText: nil
            ) { showShareSheet = true }
            
            SettingsRowButton(
                title: "バグ報告・アプリへのご意見",
                systemImage: "envelope",
                accent: accent,
                trailingText: "メール"
            ) {
                let subject = urlEncode("KaKeBoへのフィードバック")
                let body = urlEncode(defaultFeedbackBody())
                if let url = URL(string: "mailto:ken.office.arita@gmail.com?subject=\(subject)&body=\(body)") {
                    UIApplication.shared.open(url)
                }
            }
            SettingsRowButton(
                title: "バックアップを作成",
                systemImage: "arrow.down.doc",
                accent: accent,
                trailingText: "JSON形式"
            ) {
                let data = store.exportFullBackupJSON(theme: themeStore.theme)
                exportDoc = KaKeBoBackupDocument(data: data)
                showingExporter = true
            }
            SettingsRowButton(
                title: "バックアップから復元",
                systemImage: "arrow.up.doc",
                accent: accent,
                trailingText: "JSON/CSV"
            ) { showImporter = true }
        } header: {
            Text("サポート")
        }
        .listRowBackground(scheme == .dark ? Color.white.opacity(0.06) : .white)
    }
    
    private func defaultFeedbackBody() -> String {
        """
        いつも KaKeBo をご利用いただきありがとうございます。
        以下に不具合やご要望をご記入ください。
        
        ▼ 内容:
        
        ▼ 再現手順（任意）:
        
        ▼ 端末情報（任意）:
        - iOSバージョン: 
        - 端末モデル: 
        """
    }
    
    private func urlEncode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
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
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }
    static func todayString() -> String {
        let f = DateFormatter(); f.locale = .init(identifier: "ja_JP"); f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
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
//                        .symbolRenderingMode(.hierarchical)
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
