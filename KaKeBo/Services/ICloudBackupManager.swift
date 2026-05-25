//
//  Services/ICloudBackupManager.swift
//  KaKeBo
//
//  iCloud Drive 自動バックアップ管理
//  - iCloud Drive の Documents/ に保存（Files アプリから閲覧可能）
//  - 最大3世代保持
//  - 最小間隔6時間で重複防止
//  - 機種変更時にローカルデータ空なら iCloud から復元を提案
//

import Foundation

final class ICloudBackupManager {
    static let shared = ICloudBackupManager()

    private let maxGenerations = 3
    private let minimumInterval: TimeInterval = 21600 // 6時間
    private let containerID = "iCloud.com.irochi.KaKeBo"
    private let backupFolderName = "Backups"

    // 設定キー
    private let enabledKey = "kakebo.icloud.backup.enabled"
    private let lastBackupDateKey = "kakebo.icloud.backup.lastDate"

    /// iCloud バックアップが有効かどうか
    var isEnabled: Bool {
        get { UserDefaults.appGroup.bool(forKey: enabledKey) }
        set { UserDefaults.appGroup.set(newValue, forKey: enabledKey) }
    }

    /// iCloud が利用可能かどうか
    var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// iCloud Drive のバックアップフォルダ URL
    private var iCloudBackupDir: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerID) else {
            return nil
        }
        // Documents/ に保存すると Files アプリから見える
        return containerURL.appendingPathComponent("Documents").appendingPathComponent(backupFolderName)
    }

    private let backupQueue = DispatchQueue(label: "com.irochi.KaKeBo.iCloudBackup", qos: .utility)

    private init() {}

    // MARK: - 自動バックアップ実行

    /// データ保存時に呼び出す。有効 & 最小間隔超過ならバックアップ作成（バックグラウンドで実行）
    func performIfNeeded(categories: [Category], transactions: [Transaction], budgets: [Budget], frequentTemplates: [FrequentTransactionTemplate]) {
        guard isEnabled, isAvailable else { return }
        guard !transactions.isEmpty else { return }
        guard let dir = iCloudBackupDir else { return }

        // 最小間隔チェック
        if let lastDate = UserDefaults.appGroup.object(forKey: lastBackupDateKey) as? Date,
           Date().timeIntervalSince(lastDate) < minimumInterval {
            return
        }

        // バックアップデータ作成（AutoBackupManager と同じペイロード）
        let payload = buildPayload(categories: categories, transactions: transactions, budgets: budgets, frequentTemplates: frequentTemplates)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return }

        // iCloud ファイルI/Oはバックグラウンドキューで実行
        backupQueue.async { [weak self] in
            guard let self else { return }
            self.ensureDirectory(dir)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "kakebo_\(formatter.string(from: Date())).json"
            let fileURL = dir.appendingPathComponent(fileName)

            do {
                try data.write(to: fileURL, options: .atomic)
                self.pruneOldBackups(in: dir)
                DispatchQueue.main.async {
                    UserDefaults.appGroup.set(Date(), forKey: self.lastBackupDateKey)
                }
                #if DEBUG
                print("[iCloudBackup] 保存完了: \(fileName)")
                #endif
            } catch {
                #if DEBUG
                print("[iCloudBackup] 保存エラー: \(error)")
                #endif
            }
        }
    }

    // MARK: - iCloud バックアップ一覧

    /// iCloud Drive 上の利用可能なバックアップ一覧（新しい順）
    /// ダウンロード未完了のファイルはスキップし、バックグラウンドでダウンロードを開始する
    func availableBackups() -> [BackupFileInfo] {
        guard let dir = iCloudBackupDir else { return [] }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.ubiquitousItemDownloadingStatusKey]) else { return [] }

        return files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("kakebo_") }
            .compactMap { url -> BackupFileInfo? in
                // ダウンロード完了済みのファイルのみ読む
                let resourceValues = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                let status = resourceValues?.ubiquitousItemDownloadingStatus
                if status != .current {
                    // 未ダウンロード・ダウンロード中はスキップし、バックグラウンドでDL開始
                    if status == .notDownloaded {
                        try? fm.startDownloadingUbiquitousItem(at: url)
                    }
                    return nil
                }

                guard let data = try? Data(contentsOf: url),
                      let backup = try? JSONDecoder.iCloudISO8601.decode(AutoBackupPayload.self, from: data) else { return nil }
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
        return try? JSONDecoder.iCloudISO8601.decode(AutoBackupPayload.self, from: data)
    }

    // MARK: - 機種変更検出

    /// ローカルデータが空で iCloud にバックアップがある場合、復元候補を返す
    func checkForCloudRestore(currentTransactionCount: Int) -> BackupFileInfo? {
        guard currentTransactionCount == 0 else { return nil }
        guard isAvailable else { return nil }
        // iCloud に最新バックアップがあれば返す
        return availableBackups().first
    }

    // MARK: - 最終バックアップ日時

    var lastBackupDate: Date? {
        UserDefaults.appGroup.object(forKey: lastBackupDateKey) as? Date
    }

    // MARK: - Private

    private func ensureDirectory(_ dir: URL) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    private func pruneOldBackups(in dir: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }

        let backupFiles = files
            .filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("kakebo_") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // 新しい順

        if backupFiles.count > maxGenerations {
            for file in backupFiles.dropFirst(maxGenerations) {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func buildPayload(categories: [Category], transactions: [Transaction], budgets: [Budget], frequentTemplates: [FrequentTransactionTemplate]) -> AutoBackupPayload {
        return AutoBackupPayload.buildFromCurrent(
            categories: categories,
            transactions: transactions,
            budgets: budgets,
            frequentTemplates: frequentTemplates
        )
    }
}

// MARK: - JSONDecoder ヘルパー

private extension JSONDecoder {
    static let iCloudISO8601: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
