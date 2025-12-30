//
//  KaKeBoApp.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import Foundation
import SwiftUI
import CloudKit

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
    
    @Environment(\.scenePhase) private var scenePhase
    
    // 初回だけロックをかける制御
    @State private var didInitialAppear = false
    // iOS16向けの旧onChange用に前回フェーズも保持
    @State private var lastPhase: ScenePhase = .active
    
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
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .task {
//                    debugAppGroupFiles()
                    await purchase.load()

                    for metadata in AppDelegate.drainShareMetadatas() {
                        await sharedLedgerStore.handleAcceptedShareMetadata(metadata)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .cloudKitShareAccepted)) { notification in
                    Task {
                        let queued = AppDelegate.drainShareMetadatas()
                        if queued.isEmpty, let metadata = notification.object as? CKShare.Metadata {
                            await sharedLedgerStore.handleAcceptedShareMetadata(metadata)
                        } else {
                            for metadata in queued {
                                await sharedLedgerStore.handleAcceptedShareMetadata(metadata)
                            }
                        }
                    }
                }
                .onOpenURL { url in
                    Task {
                        await sharedLedgerStore.handleIncomingShareURL(url)
                    }
                }
            // 初回起動時のみ、ロック有効ならロック
                .onAppear {
                    if !didInitialAppear {
                        didInitialAppear = true
                        if lock.isEnabled {
                            lock.isLocked = true
                        }
                    }
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
}

extension Notification.Name {
    static let cloudKitShareAccepted = Notification.Name("cloudKitShareAccepted")
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

func debugAppGroups() {
    let groups = [
        "group.com.irochiTech.KaKeBo",
        "group.com.irochi.KaKeBo"
    ]
    
    for id in groups {
        let ud = UserDefaults(suiteName: id)
        
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
        print("✅ AppGroup:", id)
        print("  - containerURL:", url?.path ?? "nil")
        
        // 目印キーを書いて読めるか（アクセス可否確認）
        ud?.set(Date().description, forKey: "debug_group_probe")
        print("  - probe:", ud?.string(forKey: "debug_group_probe") ?? "nil")
        
        // そのグループの UserDefaults に何個キーがあるか（どっちに実データが居そうかのヒント）
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
        let ud = UserDefaults(suiteName: id)!
        let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
        
        let keys = ud.dictionaryRepresentation().keys
            .filter { $0 != "debug_group_probe" }
            .sorted()
        
        print("✅ AppGroup:", id)
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
            print("❌ AppGroup:", id, "containerURL nil")
            continue
        }
        
        print("✅ AppGroup:", id)
        print("  - base:", base.path)
        
        // 直下を一覧
        if let items = try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: []) {
            for u in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? u.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                let isDir = values?.isDirectory == true
                let size = values?.fileSize ?? 0
                print("  -", isDir ? "[DIR]" : "[FILE]", u.lastPathComponent, "size:", size)
            }
        }
        
        // よくある保存先もざっくり探す
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
