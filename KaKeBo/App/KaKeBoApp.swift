//
//  KaKeBoApp.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

@main
struct KaKeBoApp: App {
    @StateObject private var dataStore = DataStore()
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var purchase = PurchaseManager()
    @StateObject private var lock = AppLockManager.shared
    
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
                .environmentObject(purchase)
                .environmentObject(lock)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .task { await purchase.load() }
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
