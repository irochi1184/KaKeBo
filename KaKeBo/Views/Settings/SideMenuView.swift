//
//  Views/Settings/SideMenuView.swift
//  KaKeBo
//
//  サイドメニュー: 帳簿切替 + 設定項目一覧
//

import SwiftUI
import UserNotifications
import UniformTypeIdentifiers

struct SideMenuView: View {
    @Binding var isOpen: Bool

    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var pm: PurchaseManager
    @EnvironmentObject var lock: AppLockManager
    @EnvironmentObject var monthStartStore: MonthStartStore

    @Environment(\.colorScheme) private var scheme

    // シート管理
    @State private var sheet: Sheet?
    @State private var showPaywall = false
    @State private var showShareSheet = false
    @State private var showNotifAlert = false
    @State private var notifMessage = ""

    // バックアップ関連
    @State private var showBackupSheet = false
    @State private var showAutoBackupRestore = false
    @State private var backupTarget: BackupTarget = .personal
    @State private var backupMode: BackupMode = .export
    @State private var isProcessingBackup = false
    @State private var pendingImportTarget: BackupTarget?
    @State private var showImporter = false
    @State private var exportDoc: SettingsView.KaKeBoBackupDocument?
    @State private var showingExporter = false
    @State private var exportFilename = ""
    @State private var importReportText: String?
    @State private var showImportDone = false
    @State private var showExportDone = false
    @State private var exportDoneMessage = ""
    @State private var backupErrorMessage: String?

    @AppStorage("calendar.bottom.display.mode", store: UserDefaults.appGroup)
    private var calendarBottomMode: CalendarBottomDisplayMode = .monthTodo

    @StateObject private var todoStore = TodoStore()

    enum Sheet: Identifiable {
        case reminders, categories, recurringTodos, fixedExpenses, recurringDetect, theme, help, lock, sharedLedgers, monthStart, calendarBottomDisplay, homeCardOrder, exportData, updateHistory
        var id: String { "side-sheet-\(self)" }
    }

    private let appleWidgetURL = URL(string: "https://support.apple.com/ja-jp/HT207122")!
    private let discordURL = URL(string: "https://discord.gg/RusZAXf57n")!
    private let appStoreURL = URL(string: "https://apps.apple.com/app/id6754249349")!

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // 背景タップで閉じる
                if isOpen {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.25)) { isOpen = false } }
                }

                // メニュー本体
                HStack(spacing: 0) {
                    menuContent(accent: themeStore.theme.accentColor(for: scheme))
                        .frame(width: geo.size.width * 2 / 3)
                        .background(themeStore.theme.backgroundColor(for: scheme))
                        .offset(x: isOpen ? 0 : -geo.size.width * 2 / 3)
                    Spacer()
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isOpen)
        }
        .ignoresSafeArea()
        .sheet(item: $sheet) { s in sheetContent(s) }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showShareSheet) {
            ActivityView(activityItems: [appStoreURL])
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showBackupSheet) {
            BackupOperationSheet(
                accent: themeStore.theme.accentColor(for: scheme),
                selection: $backupTarget,
                mode: $backupMode,
                isProcessing: $isProcessingBackup
            ) { proceedBackupFlow() }
            .environmentObject(sharedLedgerStore)
        }
        .sheet(isPresented: $showAutoBackupRestore) {
            AutoBackupRestoreView()
                .environmentObject(store)
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDoc,
            contentType: .kakeboBackup,
            defaultFilename: exportFilename
        ) { result in
            if case .success(let url) = result {
                let filename = url.lastPathComponent
                exportDoneMessage = filename.isEmpty ? "バックアップ作成が完了しました。" : "バックアップ作成が完了しました。\n保存先: \(filename)"
                showExportDone = true
            } else if case .failure(let error) = result {
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
            if case .success(let urls) = result, let url = urls.first {
                let target = pendingImportTarget ?? .personal
                handleImportedURL(url, target: target)
                pendingImportTarget = nil
            } else if case .failure(let error) = result {
                importReportText = "ファイル選択に失敗: \(error.localizedDescription)"
                showImportDone = true
                pendingImportTarget = nil
            }
        }
        .alert("通知が許可されていません", isPresented: $showNotifAlert) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("閉じる", role: .cancel) {}
        } message: { Text(notifMessage) }
        .alert("バックアップ復元", isPresented: $showImportDone) {
            Button("OK", role: .cancel) {}
        } message: { Text(importReportText ?? "") }
        .alert("バックアップ作成", isPresented: $showExportDone) {
            Button("OK", role: .cancel) {}
        } message: { Text(exportDoneMessage) }
        .alert("バックアップに失敗しました", isPresented: Binding(
            get: { backupErrorMessage != nil },
            set: { _ in backupErrorMessage = nil }
        )) {
            Button("OK", role: .cancel) {}
        } message: { Text(backupErrorMessage ?? "") }
    }

    // MARK: - メニュー本体

    @ViewBuilder
    private func menuContent(accent: Color) -> some View {
        VStack(spacing: 0) {
            // ヘッダー
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("KaKeBo")
                        .font(.title2.weight(.bold))
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { isOpen = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                // 帳簿切替
                ledgerSwitcher(accent: accent)
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 16)

            Divider().padding(.horizontal, 16)

            // Premium バナー
            if !pm.isPremiumActive {
                PremiumBanner(accent: accent) { showPaywall = true }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }

            // 設定項目リスト
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    sectionHeader("各種設定")
                    settingsItems(accent: accent)

                    sectionHeader("バックアップ・書き出し")
                    backupItems(accent: accent)

                    sectionHeader("サポート")
                    supportItems(accent: accent)

                    // バージョン
                    HStack {
                        Spacer()
                        Text(appVersionLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - 帳簿切替

    @ViewBuilder
    private func ledgerSwitcher(accent: Color) -> some View {
        VStack(spacing: 8) {
            // 個人用
            Button {
                ledgerContext.setPersonal()
                withAnimation(.easeInOut(duration: 0.25)) { isOpen = false }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(ledgerContext.isPersonal ? accent : .secondary)
                    Text("個人用家計簿")
                        .foregroundStyle(.primary)
                    Spacer()
                    if ledgerContext.isPersonal {
                        Image(systemName: "checkmark")
                            .foregroundStyle(accent)
                            .font(.caption.weight(.bold))
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ledgerContext.isPersonal ? accent.opacity(0.1) : Color.clear)
                )
            }
            .buttonStyle(.plain)

            // 共有家計簿
            if !sharedLedgerStore.ledgers.isEmpty {
                ForEach(sharedLedgerStore.ledgers) { ledger in
                    let isSelected = ledgerContext.isShared && ledgerContext.selectedSharedLedgerId == ledger.id
                    Button {
                        ledgerContext.setShared(id: ledger.id)
                        Task { await sharedLedgerStore.reloadTransactions(for: ledger) }
                        withAnimation(.easeInOut(duration: 0.25)) { isOpen = false }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: ledger.icon)
                                .foregroundStyle(isSelected ? accent : .secondary)
                            Text(ledger.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(accent)
                                    .font(.caption.weight(.bold))
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? accent.opacity(0.1) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - セクション

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }

    @ViewBuilder
    private func settingsItems(accent: Color) -> some View {
        menuRow("リマインダーを管理", icon: "bell.badge", accent: accent) {
            Task {
                if await ensureNotificationRegistered() {
                    sheet = .reminders
                } else {
                    notifMessage = "現在通知の許可設定ができていません。iOSの「設定」アプリ > 通知 > KaKeBo からオンにしてください。"
                    showNotifAlert = true
                }
            }
        }
        menuRow("カテゴリを管理", icon: "square.grid.2x2", accent: accent) { sheet = .categories }
        menuRow("毎月のToDoを管理", icon: "calendar.badge.clock", accent: accent) { sheet = .recurringTodos }
        menuRow("固定費を管理", icon: "yensign.circle", accent: accent) { sheet = .fixedExpenses }
        menuRow("繰り返し支出を検出", icon: "repeat.circle", accent: accent) { sheet = .recurringDetect }
        menuRow("テーマ管理", icon: "paintpalette", accent: accent) { sheet = .theme }
        menuRow("アプリロックを設定", icon: "lock.shield", accent: accent) { sheet = .lock }
        menuRow("月の開始日を設定", icon: "calendar.badge.plus", accent: accent) { sheet = .monthStart }
        menuRow("カレンダー下部の表示", icon: "rectangle.bottomthird.inset.filled", accent: accent) { sheet = .calendarBottomDisplay }
        menuRow("ホーム画面のカード並び替え", icon: "rectangle.stack", accent: accent) { sheet = .homeCardOrder }
        menuRow("共有家計簿を管理", icon: "person.2", accent: accent) { sheet = .sharedLedgers }
    }

    @ViewBuilder
    private func backupItems(accent: Color) -> some View {
        menuRow("バックアップを作成・復元", icon: "arrow.triangle.2.circlepath", accent: accent) {
            showBackupSheet = true
        }
        menuRow("自動バックアップから復元", icon: "clock.arrow.circlepath", accent: accent) {
            showAutoBackupRestore = true
        }
        menuRow("データを書き出す", icon: "square.and.arrow.up", accent: accent) {
            sheet = .exportData
        }
        // iCloud自動バックアップ
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: "icloud.fill")
                    .foregroundStyle(accent)
                    .frame(width: 24)
                Text("iCloud自動バックアップ")
                    .font(.subheadline)
                Spacer()
                if ICloudBackupManager.shared.isAvailable {
                    Toggle("", isOn: Binding(
                        get: { ICloudBackupManager.shared.isEnabled },
                        set: { ICloudBackupManager.shared.isEnabled = $0 }
                    ))
                    .labelsHidden()
                } else {
                    Text("利用不可")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if ICloudBackupManager.shared.isEnabled {
                if let error = ICloudBackupManager.shared.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .padding(.leading, 36)
                } else if let lastDate = ICloudBackupManager.shared.lastBackupDate {
                    Text("最終: \(lastDate.formatted(.dateTime.month().day().hour().minute()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 36)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func supportItems(accent: Color) -> some View {
        menuRow("アップデート履歴", icon: "clock.arrow.circlepath", accent: accent) { sheet = .updateHistory }
        menuRow("使い方・よくある質問", icon: "questionmark.circle", accent: accent) { sheet = .help }
        menuRow("ウィジェットの使い方", icon: "apps.iphone", accent: accent) {
            UIApplication.shared.open(appleWidgetURL)
        }
        menuRow("友達にKaKeBoを共有する", icon: "square.and.arrow.up", accent: accent) {
            showShareSheet = true
        }
        menuRow("バグ報告・アプリへのご意見", icon: "envelope", accent: accent) {
            let subject = "KaKeBoへのフィードバック".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: "mailto:ken.office.arita@gmail.com?subject=\(subject)") {
                UIApplication.shared.open(url)
            }
        }
        menuRow("コミュニティへ参加する", icon: "bubble.left.and.bubble.right", accent: accent) {
            UIApplication.shared.open(discordURL)
        }
    }

    // MARK: - 汎用メニュー行

    @ViewBuilder
    private func menuRow(_ title: String, icon: String, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(accent)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - シート表示

    @ViewBuilder
    private func sheetContent(_ s: Sheet) -> some View {
        NavigationStack {
            Group {
                switch s {
                case .reminders:
                    ReminderSettingsView()
                        .environmentObject(store)
                        .environmentObject(todoStore)
                case .categories:
                    CategoryListView()
                        .environmentObject(store)
                case .recurringTodos:
                    RecurringTodoSettingsView()
                case .fixedExpenses:
                    FixedExpenseSettingsView()
                        .environmentObject(store)
                        .environmentObject(monthStartStore)
                case .theme:
                    ThemeSettingsView()
                case .help:
                    HelpFAQView()
                case .lock:
                    LockSettingsView()
                case .sharedLedgers:
                    SharedLedgerListScreen()
                        .environmentObject(sharedLedgerStore)
                case .monthStart:
                    MonthStartSettingsView()
                case .recurringDetect:
                    RecurringExpenseSuggestionsView()
                        .environmentObject(store)
                        .environmentObject(monthStartStore)
                case .calendarBottomDisplay:
                    CalendarBottomDisplaySettingsView(
                        selection: $calendarBottomMode,
                        accent: themeStore.theme.accentColor(for: scheme)
                    )
                case .homeCardOrder:
                    HomeCardOrderSettingsView(accent: themeStore.theme.accentColor(for: scheme))
                        .navigationTitle("ホーム画面のカード並び替え")
                case .exportData:
                    ExportView()
                        .environmentObject(store)
                        .environmentObject(monthStartStore)
                        .environmentObject(pm)
                        .environmentObject(themeStore)
                case .updateHistory:
                    UpdateHistoryView()
                        .environmentObject(themeStore)
                        .navigationTitle("アップデート履歴")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - バックアップ処理

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
                    data = store.exportFullBackup(theme: themeStore.theme)
                case .shared(let ledgerId):
                    guard let ledger = sharedLedgerStore.ledgers.first(where: { $0.id == ledgerId }) else {
                        throw NSError(domain: "KaKeBo", code: -1, userInfo: [NSLocalizedDescriptionKey: "選択した共有家計簿が見つかりませんでした。"])
                    }
                    data = try await sharedLedgerStore.exportBackup(for: ledger)
                }
                await MainActor.run {
                    exportDoc = SettingsView.KaKeBoBackupDocument(data: data)
                    exportFilename = backupFilename(for: target)
                    showingExporter = true
                }
            } catch {
                await MainActor.run {
                    backupErrorMessage = "バックアップ作成に失敗しました: \(error.localizedDescription)"
                }
            }
            await MainActor.run { isProcessingBackup = false }
        }
    }

    private func handleImportedURL(_ url: URL, target: BackupTarget) {
        Task(priority: .userInitiated) {
            await MainActor.run { isProcessingBackup = true }
            let needsSecurity = url.startAccessingSecurityScopedResource()
            defer { if needsSecurity { url.stopAccessingSecurityScopedResource() } }

            do {
                let data = try Data(contentsOf: url)
                let report: DataStore.ImportReport
                switch target {
                case .personal:
                    report = try await MainActor.run {
                        try store.importBackup(
                            data: data,
                            applyTheme: { themeStore.theme = $0 },
                            applyMonthStartSettings: { monthStartStore.settings = $0 }
                        )
                    }
                case .shared(let ledgerId):
                    guard let ledger = sharedLedgerStore.ledgers.first(where: { $0.id == ledgerId }) else {
                        throw NSError(domain: "KaKeBo", code: -1, userInfo: [NSLocalizedDescriptionKey: "対象の共有家計簿が見つかりませんでした。"])
                    }
                    report = try await sharedLedgerStore.importBackup(data: data, to: ledger)
                }
                await MainActor.run {
                    let name = backupTargetName(for: target)
                    importReportText = "復元完了（\(name)）：取込 \(report.inserted) 件 / 新規カテゴリ \(report.createdCategories) 件 / スキップ \(report.skipped) 件"
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

    private func backupFilename(for target: BackupTarget) -> String {
        let baseName = backupTargetName(for: target)
        let safeName = baseName.replacingOccurrences(of: "[^0-9A-Za-zぁ-んァ-ン一-龠_-]", with: "_", options: .regularExpression)
        let f = DateFormatter(); f.locale = .init(identifier: "ja_JP"); f.dateFormat = "yyyyMMdd_HHmmss"
        return "KaKeBo_\(safeName)_backup_\(f.string(from: Date())).kakebo"
    }

    private func backupTargetName(for target: BackupTarget) -> String {
        switch target {
        case .personal: return "個人用"
        case .shared(let ledgerId):
            return sharedLedgerStore.ledgers.first(where: { $0.id == ledgerId })?.name ?? "共有家計簿"
        }
    }

    private var appVersionLabel: String {
        let version = AppVersion.current
        return "バージョン \(version)"
    }
}

// MARK: - CalendarBottomDisplaySettingsView（SideMenuからも使用可能にするためinternal化）

struct CalendarBottomDisplaySettingsView: View {
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
        .listRowBackground(FlatListRowBackground(appliesFlatBorder: false))
        .navigationTitle("カレンダー下部の表示")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") { dismiss() }
            }
        }
    }
}
