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
import CloudKit

struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var pm: PurchaseManager
    @EnvironmentObject var lock: AppLockManager
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var monthStartStore: MonthStartStore
    
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    
    @AppStorage("reminder.enabled", store: .appGroup) private var enabled: Bool = true
    @AppStorage("reminder.time", store: .appGroup) private var timeRaw: Double = Self.defaultTime.timeIntervalSinceReferenceDate
    @AppStorage("calendar.bottom.display.mode", store: .appGroup) private var calendarBottomMode: CalendarBottomDisplayMode = .monthTodo
    
    // ▼ リマインダー統一：Settings 内で共有する ToDo ストア（今日の件数評価などに使う）
    @StateObject private var todoStore = TodoStore()
    
    @State private var sheet: Sheet?
    
    @AppStorage("kakebo.recurring.templates", store: .appGroup) private var templatesData: Data = Data()
    @State private var templates: [RecurringTodoTemplate] = []
    @State private var showNotifAlert = false
    @State private var notifMessage: String = "現在通知の許可設定ができていません。iOSの「設定」アプリから通知を許可してください。"
    @State private var showPaywall = false
    @State private var showShareSheet = false
    // バックアップ作成／復元
    @State private var showImporter = false
    @State private var exportDoc: KaKeBoBackupDocument? = nil

    init() {
        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: ["reminder.enabled", "reminder.time", "kakebo.recurring.templates"])
        _enabled = AppStorage(wrappedValue: true, "reminder.enabled", store: defaults)
        _timeRaw = AppStorage(wrappedValue: Self.defaultTime.timeIntervalSinceReferenceDate, "reminder.time", store: defaults)
        _templatesData = AppStorage(wrappedValue: Data(), "kakebo.recurring.templates", store: defaults)
    }
    @State private var showingExporter = false
    @State private var importReportText: String? = nil
    @State private var showImportDone = false
    @State private var showExportDone = false
    @State private var exportDoneMessage: String = "バックアップ作成が完了しました。"
    @State private var showLockSheet = false
    @State private var showBackupSheet = false
    @State private var backupTarget: BackupTarget = .personal
    @State private var backupMode: BackupMode = .export
    @State private var pendingImportTarget: BackupTarget?
    @State private var isProcessingBackup = false
    @State private var exportFilename: String = "KaKeBo_backup_\(Self.todayString()).kakebo"
    @State private var backupErrorMessage: String?
    
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
        case reminders, categories, recurringTodos, fixedExpenses, theme, help, lock, sharedLedgers, monthStart, calendarBottomDisplay
        var id: String { "sheet-\(self)" }
    }
    // 外部URL
    private let appleWidgetURL = URL(string: "https://support.apple.com/ja-jp/HT207122")!
    private let discordURL = URL(string: "https://discord.gg/RusZAXf57n")!
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
        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: [DataStore.fixedTemplatesKey])
        let data = defaults.migratedData(forKey: DataStore.fixedTemplatesKey) ?? Data()
        let count = (try? JSONDecoder().decode([FixedExpenseTemplate].self, from: data))?.count ?? 0
        return "\(count)件"
    }
    private var reminderCountText: String {
        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: [ReminderStore.storageKey])
        let data = defaults.migratedData(forKey: ReminderStore.storageKey) ?? Data()
        let rules = (try? JSONDecoder().decode([ReminderRule].self, from: data)) ?? []
        let enabled = rules.filter { $0.enabled }.count
        return "有効 \(enabled)/\(rules.count) 件"
    }
    
    var body: some View {
        let accent = themeStore.theme.accentColor(for: scheme)
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    if !pm.isPremiumActive {
                        PremiumBanner(accent: accent) { showPaywall = true }
                            .padding(.horizontal)
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                            .background(themeStore.theme.backgroundColor(for: scheme).opacity(0.7))
                    }
                    
                    Form {
                        settingsSection(accent: accent)
                        backupSection(accent: accent)
                        supportSection(accent: accent)
                    }
                    .scrollContentBackground(.hidden)
                    .safeAreaInset(edge: .bottom) {
                        versionFooter
                    }
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

                    case .lock:
                        NavigationStack {
                            LockSettingsView()
                                .navigationTitle("アプリロック")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)

                    case .sharedLedgers:
                        NavigationStack {
                            SharedLedgerListScreen()
                                .environmentObject(sharedLedgerStore)
                                .navigationTitle("共有家計簿")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)

                    case .monthStart:
                        NavigationStack {
                            MonthStartSettingsView()
                                .navigationTitle("月の開始日")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)

                    case .calendarBottomDisplay:
                        NavigationStack {
                            CalendarBottomDisplaySettingsView(
                                selection: $calendarBottomMode,
                                accent: accent
                            )
                            .navigationTitle("カレンダー下部の表示")
                            .navigationBarTitleDisplayMode(.inline)
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)

                    }
                }
                // 共有
                .sheet(isPresented: $showShareSheet) {
                    ActivityView(activityItems: [appStoreURL])
                        .presentationDetents([.medium])
                }
                // Paywall
                .sheet(isPresented: $showPaywall) {
                    PremiumPaywallView(accent: accent)
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)
                }
                // バックアップ操作
                .sheet(isPresented: $showBackupSheet) {
                    BackupOperationSheet(
                        accent: accent,
                        selection: $backupTarget,
                        mode: $backupMode,
                        isProcessing: $isProcessingBackup
                    ) {
                        proceedBackupFlow()
                    }
                    .environmentObject(sharedLedgerStore)
                }
                // ロック設定
                .sheet(isPresented: $showLockSheet) {
                    NavigationStack {
                        LockSettingsView()
                            .environmentObject(lock)
                            .navigationTitle("アプリロック")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
                    }
                    .background(themeStore.theme.backgroundColor(for: scheme))
                }
                
                if isProcessingBackup {
                    backupProcessingOverlay
                }
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
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success(let url):
                let filename = url.lastPathComponent
                exportDoneMessage = filename.isEmpty ? "バックアップ作成が完了しました。" : "バックアップ作成が完了しました。\n保存先: \(filename)"
                showExportDone = true
            case .failure(let error):
                let cocoaError = error as? CocoaError
                if cocoaError?.code != .userCancelled {
                    backupErrorMessage = "バックアップ保存に失敗しました: \(error.localizedDescription)"
                }
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
                    pendingImportTarget = nil
                    return
                }
                let target = pendingImportTarget ?? .personal
                handleImportedURL(url, target: target)
                pendingImportTarget = nil
            case .failure(let error):
                importReportText = "ファイル選択に失敗: \(error.localizedDescription)"
                showImportDone = true
                pendingImportTarget = nil
            }
        }
        .alert("バックアップ復元", isPresented: $showImportDone) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importReportText ?? "")
        }
        .alert("バックアップ作成", isPresented: $showExportDone) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(exportDoneMessage)
        }
        .alert("バックアップに失敗しました", isPresented: Binding(
            get: { backupErrorMessage != nil },
            set: { _ in backupErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(backupErrorMessage ?? "")
        }
    }
    
    private func handleImportedURL(_ url: URL, target: BackupTarget) {
        Task(priority: .userInitiated) {
            await MainActor.run { isProcessingBackup = true }
            let needsSecurity = url.startAccessingSecurityScopedResource()
            defer {
                if needsSecurity {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            do {
                let data = try Data(contentsOf: url)
                let report: DataStore.ImportReport
                switch target {
                case .personal:
                    report = try await MainActor.run { () -> DataStore.ImportReport in
                        try store.importBackup(
                            data: data,
                            applyTheme: { restoredTheme in
                                themeStore.theme = restoredTheme
                            },
                            applyMonthStartSettings: { restoredSettings in
                                monthStartStore.settings = restoredSettings
                            }
                        )
                    }
                case .shared(let ledgerId):
                    guard let ledger = sharedLedgerStore.ledgers.first(where: { $0.id == ledgerId }) else {
                        throw NSError(domain: "KaKeBo", code: -1, userInfo: [NSLocalizedDescriptionKey: "対象の共有家計簿が見つかりませんでした。"])
                    }
                    report = try await sharedLedgerStore.importBackup(data: data, to: ledger)
                }
                await MainActor.run {
                    importReportText = "復元完了（\(backupTargetName(for: target))）：取込 \(report.inserted) 件 / 新規カテゴリ \(report.createdCategories) 件 / スキップ \(report.skipped) 件"
                    showImportDone = true
                    isProcessingBackup = false
                }
            } catch {
                await MainActor.run {
                    importReportText = "復元に失敗（\(backupTargetName(for: target))）: \(error.localizedDescription)"
                    showImportDone = true
                    isProcessingBackup = false
                }
            }
        }
    }
    
    private func proceedBackupFlow() {
        switch backupMode {
        case .export:
            startBackupExport(for: backupTarget)
        case .restore:
            pendingImportTarget = backupTarget
            showImporter = true
        }
    }
    
    private func startBackupExport(for target: BackupTarget) {
        isProcessingBackup = true
        Task(priority: .userInitiated) {
            do {
                let data: Data
                switch target {
                case .personal:
                    data = store.exportFullBackupJSON(theme: themeStore.theme)
                case .shared(let ledgerId):
                    guard let ledger = sharedLedgerStore.ledgers.first(where: { $0.id == ledgerId }) else {
                        throw NSError(domain: "KaKeBo", code: -1, userInfo: [NSLocalizedDescriptionKey: "選択した共有家計簿が見つかりませんでした。"])
                    }
                    data = try await sharedLedgerStore.exportBackup(for: ledger)
                }
                await MainActor.run {
                    exportDoc = KaKeBoBackupDocument(data: data)
                    exportFilename = backupFilename(for: target)
                    showingExporter = true
                }
            } catch {
                await MainActor.run {
                    backupErrorMessage = "バックアップ作成に失敗しました: \(error.localizedDescription)"
                }
            }
            await MainActor.run {
                isProcessingBackup = false
            }
        }
    }

    private var backupProcessingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                Text(backupProcessingText)
                    .font(.callout)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .transition(.opacity)
    }

    private var backupProcessingText: String {
        switch backupMode {
        case .export:
            return "バックアップを作成中…"
        case .restore:
            return "復元中…"
        }
    }
    
    // MARK: - Sections split
    
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
                    if await ensureNotificationRegistered() {
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
            
            SettingsRowButton(
                title: "アプリロックを設定",
                systemImage: "lock.shield",
                accent: accent,
                trailingText: nil
            ) { sheet = .lock }

            SettingsRowButton(
                title: "月の開始日を設定",
                systemImage: "calendar.badge.plus",
                accent: accent,
                trailingText: monthStartSummary
            ) { sheet = .monthStart }

            SettingsRowButton(
                title: "カレンダー下部の表示",
                systemImage: "rectangle.bottomthird.inset.filled",
                accent: accent,
                trailingText: calendarBottomMode.title
            ) { sheet = .calendarBottomDisplay }

            SettingsRowButton(
                title: "共有家計簿を管理",
                systemImage: "person.2",
                accent: accent,
                trailingText: "\(sharedLedgerStore.ledgers.count)件"
            ) {
                sheet = .sharedLedgers
            }

        } header: {
            Text("各種設定")
        }
        .listRowBackground(scheme == .dark ? Color.white.opacity(0.06) : .white)

    }
    
    @ViewBuilder
    private func backupSection(accent: Color) -> some View {
        Section {
            SettingsRowButton(
                title: "バックアップを作成・復元",
                systemImage: "arrow.triangle.2.circlepath",
                accent: accent,
                trailingText: backupStatusText
            ) {
                showBackupSheet = true
            }
        } header: {
            Text("バックアップを作成・復元")
        } footer: {
            Text("個人用または共有家計簿を選び、作成・復元を実行できます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                title: "開発者・利用者コミュニティへ参加する",
                systemImage: "apps.iphone",
                accent: accent,
                trailingText: "Discord"
            ) { UIApplication.shared.open(discordURL) }
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
    
    private func backupFilename(for target: BackupTarget) -> String {
        let baseName = backupTargetName(for: target)
        let safeName = baseName.replacingOccurrences(of: "[^0-9A-Za-zぁ-んァ-ン一-龠_-]", with: "_", options: .regularExpression)
        return "KaKeBo_\(safeName)_backup_\(Self.todayString()).kakebo"
    }
    
    private var backupStatusText: String {
        let actionText = backupMode == .export ? "作成" : "復元"
        return "\(backupTargetName(for: backupTarget)) / \(actionText)"
    }
    
    private func backupTargetName(for target: BackupTarget) -> String {
        switch target {
        case .personal:
            return "個人用"
        case .shared(let ledgerId):
            return sharedLedgerStore.ledgers.first(where: { $0.id == ledgerId })?.name ?? "共有家計簿"
        }
    }
    
    private func showLockSettingsSheet() { showLockSheet = true }

    private var appVersionLabel: String {
        let version = AppVersion.current
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? "バージョン \(version)" : "バージョン \(version) (\(build))"
    }

    private var versionFooter: some View {
        HStack {
            Spacer()
            Text(appVersionLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 8)
        .background(.thinMaterial)
    }

    private var monthStartSummary: String {
        let s = monthStartStore.settings
        let boundary = s.boundaryType == .startDay ? "開始日" : "締め日"
        let prefix = s.isCustomStartEnabled ? "毎月\(s.startDay)日を\(boundary)に" : "毎月1日"
        let suffix: String
        switch s.holidayAdjustment {
        case .none: suffix = "休日はそのまま"
        case .previousWeekday: suffix = "休日は前倒し"
        case .nextWeekday: suffix = "休日は後ろ倒し"
        }
        return s.isCustomStartEnabled ? "\(prefix) / \(suffix)" : prefix
    }
}

// ======================================================

private struct CalendarBottomDisplaySettingsView: View {
    @Binding var selection: CalendarBottomDisplayMode
    let accent: Color
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                ForEach(CalendarBottomDisplayMode.allCases) { mode in
                    Button {
                        selection = mode
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mode.title)
                                    .foregroundStyle(.primary)
                                Text(mode.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") { dismiss() }
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
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundStyle(accent)
                }
                Spacer()
                if let trailingText {
                    Text(trailingText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// 既存のユーティリティ（変更なし）
func ensureNotificationRegistered() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let settings = await withCheckedContinuation { (c: CheckedContinuation<UNNotificationSettings, Never>) in
        center.getNotificationSettings { c.resume(returning: $0) }
    }
    switch settings.authorizationStatus {
    case .notDetermined:
        let ok = await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                c.resume(returning: granted)
            }
        }
        return ok
    case .authorized, .provisional, .ephemeral:
        return true
    default:
        return false
    }
}
