//
//  Views/RootTabView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @State private var showSettings = false
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house.fill") }
            CalendarScreen()
                .tabItem { Label("カレンダー", systemImage: "calendar") }
            ReportsView()
                .tabItem { Label("レポート", systemImage: "chart.pie.fill") }
            AllTransactionsView()
                .tabItem { Label("履歴", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
        }
        .overlay(TutorialGate())
        .overlay(UpdateNoticeGate())
        .overlay(LoginMilestoneReviewGate())
        .tint(themeStore.theme.accentColor(for: scheme))
    }
}
