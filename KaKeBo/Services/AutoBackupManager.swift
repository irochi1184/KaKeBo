//
//  Services/AutoBackupManager.swift
//  KaKeBo
//
//  自動バックアップ管理
//  - AppGroupコンテナ内の backups/ フォルダに世代管理で保存
//  - 最小間隔（1時間）で重複防止
//  - 最大5世代保持、古いものから自動削除
//  - 起動時にデータ消失を検知して復元を提案
//

import Foundation

final class AutoBackupManager {
    static let shared = AutoBackupManager()

    private let maxGenerations = 5
    private let minimumInterval: TimeInterval = 3600 // 1時間
    private let backupDirName = "backups"
    private let metadataFileName = "backup_metadata.json"
    private let backupQueue = DispatchQueue(label: "com.irochi.KaKeBo.autoBackup", qos: .utility)

    private var backupDir: URL? {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else { return nil }
        return base.appendingPathComponent(backupDirName)
    }

    private init() {
        ensureBackupDirectory()
    }

    // MARK: - 自動バックアップ実行

    /// データ保存時に呼び出す。最小間隔を超えていればバックアップを作成
    func performIfNeeded(categories: [Category], transactions: [Transaction], budgets: [Budget], frequentTemplates: [FrequentTransactionTemplate]) {
        guard let dir = backupDir else { return }
        guard !transactions.isEmpty else { return } // 空データはバックアップしない

        // 最小間隔チェック
        if let latest = latestBackupDate(), Date().timeIntervalSince(latest) < minimumInterval {
            return
        }

        // 共通ビルダーでペイロード作成（メインスレッドでデータ取得）
        let backup = AutoBackupPayload.buildFromCurrent(
            categories: categories,
            transactions: transactions,
            budgets: budgets,
            frequentTemplates: frequentTemplates
        )

        // ファイルI/Oはバックグラウンドキューで実行
        backupQueue.async { [weak self] in
            guard let self else { return }

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(backup) else { return }

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "auto_\(formatter.string(from: Date())).json"
            let fileURL = dir.appendingPathComponent(fileName)

            do {
                try data.write(to: fileURL, options: .atomic)
                self.pruneOldBackups()
                // メタデータはメインスレッドから読まれるため、書き込みもメインで行い競合を防ぐ
                DispatchQueue.main.async {
                    self.saveMetadata(backup.metadata)
                }
            } catch {
                #if DEBUG
                print("AutoBackup write error: \(error)")
                #endif
            }
        }

        // iCloud Drive にも保存
        ICloudBackupManager.shared.performIfNeeded(
            categories: categories,
            transactions: transactions,
            budgets: budgets,
            frequentTemplates: frequentTemplates
        )
    }

    // MARK: - バックアップ一覧・復元

    /// 利用可能なバックアップ一覧（新しい順）
    func availableBackups() -> [BackupFileInfo] {
        guard let dir = backupDir else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey]) else { return [] }

        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("auto_") }
            .compactMap { url -> BackupFileInfo? in
                guard let data = try? Data(contentsOf: url),
                      let backup = try? JSONDecoder.iso8601.decode(AutoBackupPayload.self, from: data) else { return nil }
                return BackupFileInfo(
                    url: url,
                    date: backup.metadata.date,
                    transactionCount: backup.metadata.transactionCount,
                    categoryCount: backup.metadata.categoryCount
                )
            }
            .sorted { $0.date > $1.date }
    }

    /// 指定バックアップからデータを復元
    func restore(from info: BackupFileInfo) -> AutoBackupPayload? {
        guard let data = try? Data(contentsOf: info.url) else { return nil }
        return try? JSONDecoder.iso8601.decode(AutoBackupPayload.self, from: data)
    }

    // MARK: - データ消失検知

    /// 前回バックアップ時の取引件数と比較して、データが消失した可能性があるか判定
    func detectDataLoss(currentTransactionCount: Int) -> DataLossCheckResult {
        guard let metadata = loadMetadata() else { return .noBaseline }
        guard metadata.transactionCount > 0 else { return .ok }

        if currentTransactionCount == 0 && metadata.transactionCount > 0 {
            return .totalLoss(lastKnownCount: metadata.transactionCount)
        }

        // 50%以上減少した場合も警告
        let ratio = Double(currentTransactionCount) / Double(metadata.transactionCount)
        if ratio < 0.5 {
            return .significantLoss(
                currentCount: currentTransactionCount,
                lastKnownCount: metadata.transactionCount
            )
        }

        return .ok
    }

    // MARK: - Private

    private func ensureBackupDirectory() {
        guard let dir = backupDir else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func latestBackupDate() -> Date? {
        loadMetadata()?.date
    }

    private func pruneOldBackups() {
        guard let dir = backupDir else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        let backupFiles = files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("auto_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // 新しい順

        if backupFiles.count > maxGenerations {
            for file in backupFiles.dropFirst(maxGenerations) {
                try? fm.removeItem(at: file)
            }
        }
    }

    // メタデータ（最後のバックアップ情報）を保存・読み込み
    private func saveMetadata(_ metadata: BackupMetadata) {
        guard let dir = backupDir else { return }
        let url = dir.appendingPathComponent(metadataFileName)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(metadata) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadMetadata() -> BackupMetadata? {
        guard let dir = backupDir else { return nil }
        let url = dir.appendingPathComponent(metadataFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.iso8601.decode(BackupMetadata.self, from: data)
    }
}

// MARK: - データモデル

struct BackupMetadata: Codable {
    let date: Date
    let transactionCount: Int
    let categoryCount: Int
}

struct AutoBackupPayload: Codable {
    let metadata: BackupMetadata
    let categories: [Category]
    let transactions: [Transaction]
    let budgets: [Budget]
    // UserDefaults に保存されている追加データ
    var fixedExpenses: [FixedExpenseTemplate]?
    var frequentTemplates: [FrequentTransactionTemplate]?
    var recurringTodos: [RecurringTodoTemplate]?
    var dayNotes: [String: String]?
    var monthStartSettings: MonthStartSettings?
    var theme: AppTheme?

    /// 現在のデータからバックアップペイロードを構築
    static func buildFromCurrent(categories: [Category], transactions: [Transaction], budgets: [Budget], frequentTemplates: [FrequentTransactionTemplate]) -> AutoBackupPayload {
        let defaults = UserDefaults.appGroup
        let fixedExpenses: [FixedExpenseTemplate]? = {
            defaults.migrateIfNeeded(keys: [DataStore.fixedTemplatesKey])
            guard let data = defaults.migratedData(forKey: DataStore.fixedTemplatesKey) else { return nil }
            return try? JSONDecoder().decode([FixedExpenseTemplate].self, from: data)
        }()
        let recurringTodos: [RecurringTodoTemplate]? = {
            guard let data = defaults.migratedData(forKey: "kakebo.recurring.templates") else { return nil }
            return try? JSONDecoder().decode([RecurringTodoTemplate].self, from: data)
        }()
        let dayNotes: [String: String]? = {
            guard let data = defaults.migratedData(forKey: "kakebo.daynotes.v1") else { return nil }
            return try? JSONDecoder().decode([String: String].self, from: data)
        }()
        let monthStartSettings: MonthStartSettings? = {
            let ud = UserDefaults(suiteName: AppGroup.id) ?? .standard
            guard let data = ud.data(forKey: "kakebo.monthStart.settings") else { return nil }
            return try? JSONDecoder().decode(MonthStartSettings.self, from: data)
        }()
        let theme: AppTheme? = {
            let ud = UserDefaults(suiteName: AppGroup.id) ?? .standard
            guard let data = ud.data(forKey: "kakebo.theme.data") else { return nil }
            return try? JSONDecoder().decode(AppTheme.self, from: data)
        }()

        return AutoBackupPayload(
            metadata: BackupMetadata(
                date: Date(),
                transactionCount: transactions.count,
                categoryCount: categories.count
            ),
            categories: categories,
            transactions: transactions,
            budgets: budgets,
            fixedExpenses: fixedExpenses,
            frequentTemplates: frequentTemplates.isEmpty ? nil : frequentTemplates,
            recurringTodos: recurringTodos,
            dayNotes: dayNotes,
            monthStartSettings: monthStartSettings,
            theme: theme
        )
    }
}

struct BackupFileInfo: Identifiable {
    let url: URL
    let date: Date
    let transactionCount: Int
    let categoryCount: Int
    var id: URL { url }
}

enum DataLossCheckResult {
    case ok
    case noBaseline // まだバックアップがない（初回起動など）
    case totalLoss(lastKnownCount: Int)
    case significantLoss(currentCount: Int, lastKnownCount: Int)

    var needsRecovery: Bool {
        switch self {
        case .totalLoss, .significantLoss: return true
        case .ok, .noBaseline: return false
        }
    }
}

// MARK: - JSONDecoder ヘルパー

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
