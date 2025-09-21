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
    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(dataStore)
                .environment(\.locale, Locale(identifier: "ja_JP"))
        }
    }
}
