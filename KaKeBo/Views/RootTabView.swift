//
//  Views/RootTabView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct RootTabView: View {
    @EnvironmentObject var store: DataStore
    @State private var showSettings = false
    
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("ホーム", systemImage: "house.fill") }
//            CategoryListView()
//                .tabItem { Label("カテゴリ", systemImage: "square.grid.2x2.fill") }
            CalendarScreen()
                .tabItem { Label("カレンダー", systemImage: "calendar") }
            ReportsView()
                .tabItem { Label("レポート", systemImage: "chart.pie.fill") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
        }
    }
}
