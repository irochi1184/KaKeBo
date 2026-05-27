//
//  KaKeBoApp.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import Foundation
import SwiftUI
import CloudKit
import Combine

@main
struct KaKeBoApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dataStore = DataStore()
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var sharedLedgerStore = SharedLedgerStore()
    @StateObject private var purchase = PurchaseManager()
    @StateObject private var ledgerContext = LedgerContext()
    @StateObject private var lock = AppLockManager.shared
    @StateObject private var monthStartStore = MonthStartStore()
    @StateObject private var appRoute = AppRoute()
    
    @Environment(\.scenePhase) private var scenePhase

    // 初回だけロックをかける制御
    @State private var didInitialAppear = false
    // iOS16向けの旧onChange用に前回フェーズも保持
    @State private var lastPhase: ScenePhase = .active
    // データ復元提案
    @State private var showDataRecovery = false
    @State private var dataLossResult: DataLossCheckResult = .ok
    
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(dataStore)
                .environmentObject(themeStore)
                .environmentObject(sharedLedgerStore)
                .environmentObject(purchase)
                .environmentObject(lock)
                .environmentObject(ledgerContext)
                .environmentObject(monthStartStore)
                .environmentObject(appRoute)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .task {
                    let pending = CloudKitShareAcceptanceQueue.shared.drain()
                    for metadata in pending {
                        await sharedLedgerStore.acceptShare(metadata)
                    }
                }
                .task {
                    await purchase.load()
                    PhoneSessionManager.shared.configure(with: dataStore)
                }
                .onReceive(NotificationCenter.default.publisher(for: .cloudKitShareAccepted)) { _ in
                    let metadatas = CloudKitShareAcceptanceQueue.shared.drain()
                    Task {
                        for metadata in metadatas {
                            await sharedLedgerStore.acceptShare(metadata)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .cloudKitDatabaseChanged)) { _ in
                    Task {
                        await sharedLedgerStore.handleRemoteChange()
                    }
                }
                .onReceive(sharedLedgerStore.$lastAcceptedLedgerID.compactMap { $0 }) { ledgerID in
                    ledgerContext.setShared(id: ledgerID)
                    print("✅ [KaKeBoApp] switched to accepted shared ledger id=\(ledgerID.recordName)")
                    sharedLedgerStore.lastAcceptedLedgerID = nil
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    print("ℹ️ [KaKeBoApp] continueUserActivity received: \(url.absoluteString)")
                    Task {
                        do {
                            let metadata = try await CKContainer.default().shareMetadata(for: url)
                            print("ℹ️ [KaKeBoApp] shareMetadata resolved (continueUserActivity): container=\(metadata.containerIdentifier)")
                            CloudKitShareAcceptanceQueue.shared.enqueue(metadata)
                        } catch {
                            print("❌ [KaKeBoApp] shareMetadata error via continueUserActivity for url=\(url.absoluteString): \(error)")
                        }
                    }
                }
                .onOpenURL { url in
                    if !appRoute.handle(url: url) {
                        print("ℹ️ [KaKeBoApp] onOpenURL received: \(url.absoluteString)")
                        Task {
                            do {
                                let metadata = try await CKContainer.default().shareMetadata(for: url)
                                print("ℹ️ [KaKeBoApp] shareMetadata resolved: container=\(metadata.containerIdentifier)")
                                CloudKitShareAcceptanceQueue.shared.enqueue(metadata)
                            } catch {
                                print("❌ [KaKeBoApp] shareMetadata error for url=\(url.absoluteString): \(error)")
                            }
                        }
                    }
                }
            // 初回起動時のみ、ロック有効ならロック＋データ消失チェック
                .onAppear {
                    #if DEBUG
                    print("ℹ️ [KaKeBoApp] onAppear transactions=\(dataStore.transactions.count) categories=\(dataStore.categories.count)")
                    #endif
                    ReviewRequestManager.shared.registerFirstLaunchIfNeeded()
                    if !didInitialAppear {
                        didInitialAppear = true
                        if lock.isEnabled {
                            lock.isLocked = true
                        }
                        // データ消失チェック（エラー時は安全にスキップ）
                        let result = AutoBackupManager.shared.detectDataLoss(
                            currentTransactionCount: dataStore.transactions.count
                        )
                        if result.needsRecovery {
                            dataLossResult = result
                            showDataRecovery = true
                        }
                        // iCloud からの復元チェック（ローカルが空で iCloud にバックアップがある場合）
                        else {
                            // checkForCloudRestore が nil を返すケース（iCloud未ログイン等）も安全にスキップ
                            if let cloudBackup = ICloudBackupManager.shared.checkForCloudRestore(
                                currentTransactionCount: dataStore.transactions.count
                            ) {
                                dataLossResult = .totalLoss(lastKnownCount: cloudBackup.transactionCount)
                                showDataRecovery = true
                            }
                        }
                    }
                }
                .fullScreenCover(isPresented: $showDataRecovery) {
                    DataRecoveryView(
                        lossResult: dataLossResult,
                        onRestore: { backupInfo in
                            restoreFromAutoBackup(backupInfo)
                        },
                        onSkip: {
                            showDataRecovery = false
                        }
                    )
                }
            // iOS 17 以降は2引数 onChange を使い、background→active のみでロック
                .modifier(ScenePhaseLockGate(scenePhase: scenePhase, lock: lock, lastPhase: $lastPhase))
            // ロック画面
                .fullScreenCover(
                    isPresented: Binding<Bool>(
                        get: { lock.isLocked },
                        set: { if !$0 { lock.isLocked = false } }
                    )
                ) {
                    LockScreenView()
                        .environmentObject(lock)
                        .interactiveDismissDisabled(true)
                }
        }
    }

    private func restoreFromAutoBackup(_ info: BackupFileInfo) {
        guard let payload = AutoBackupManager.shared.restore(from: info) else {
            showDataRecovery = false
            return
        }
        dataStore.restoreFromAutoBackup(payload: payload)
        showDataRecovery = false
    }
}

extension Notification.Name {
    static let cloudKitShareAccepted = Notification.Name("cloudKitShareAccepted")
    static let cloudKitDatabaseChanged = Notification.Name("cloudKitDatabaseChanged")
}

/// background→active の時だけロックを復帰させるゲート
private struct ScenePhaseLockGate: ViewModifier {
    let scenePhase: ScenePhase
    let lock: AppLockManager
    @Binding var lastPhase: ScenePhase
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if oldPhase == .background && newPhase == .active {
                        lock.lockOnActivateIfEnabled()  // ← ここでのみ復帰ロック
                    }
                    lastPhase = newPhase
                }
        } else {
            content
                .onChange(of: scenePhase) { newPhase in
                    // iOS16系は oldPhase を自前で追跡
                    if lastPhase == .background && newPhase == .active {
                        lock.lockOnActivateIfEnabled()
                    }
                    lastPhase = newPhase
                }
        }
    }
}

#if DEBUG
func debugAppGroups() {
    let groups = [
        "group.com.irochiTech.KaKeBo",
        "group.com.irochi.KaKeBo"
    ]

    for id in groups {
        let ud = UserDefaults(suiteName: id)

        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
        print("AppGroup:", id)
        print("  - containerURL:", url?.path ?? "nil")

        ud?.set(Date().description, forKey: "debug_group_probe")
        print("  - probe:", ud?.string(forKey: "debug_group_probe") ?? "nil")

        let count = ud?.dictionaryRepresentation().keys.count ?? -1
        print("  - keys:", count)
    }
}

func debugAppGroupsDeep() {
    let groups = [
        "group.com.irochiTech.KaKeBo",
        "group.com.irochi.KaKeBo"
    ]

    for id in groups {
        guard let ud = UserDefaults(suiteName: id) else { continue }
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)

        let keys = ud.dictionaryRepresentation().keys
            .filter { $0 != "debug_group_probe" }
            .sorted()

        print("AppGroup:", id)
        print("  - containerURL:", url?.path ?? "nil")
        print("  - keys(\(keys.count)):", keys)
    }
}

func debugAppGroupFiles() {
    let groups = [
        "group.com.irochiTech.KaKeBo",
        "group.com.irochi.KaKeBo"
    ]

    let fm = FileManager.default

    for id in groups {
        guard let base = fm.containerURL(forSecurityApplicationGroupIdentifier: id) else {
            print("AppGroup:", id, "containerURL nil")
            continue
        }

        print("AppGroup:", id)
        print("  - base:", base.path)

        if let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: []) {
            for u in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                let isDir = values?.isDirectory == true
                let size = values?.fileSize ?? 0
                print("  -", isDir ? "[DIR]" : "[FILE]", u.lastPathComponent, "size:", size)
            }
        }

        let candidates = [
            base.appendingPathComponent("Library"),
            base.appendingPathComponent("Documents"),
            base.appendingPathComponent("tmp")
        ]
        for c in candidates {
            if fm.fileExists(atPath: c.path) {
                print("  - exists:", c.lastPathComponent)
            }
        }
    }
}
#endif
