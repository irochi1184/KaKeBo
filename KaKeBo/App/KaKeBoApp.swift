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
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(dataStore)
                .environmentObject(themeStore)
                .environmentObject(purchase)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .task {
//                    await purchase.beginListeningForUpdates()
                    await purchase.load()
                }
        }
    }
}
