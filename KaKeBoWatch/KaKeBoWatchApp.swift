//
//  KaKeBoWatchApp.swift
//  KaKeBoWatch
//
//  Apple Watch 向け家計簿アプリ
//  - よく使うテンプレートからの素早い支出入力
//  - 当日/当月の支出サマリー表示
//

import SwiftUI

@main
struct KaKeBoWatchApp: App {
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environmentObject(sessionManager)
        }
    }
}
