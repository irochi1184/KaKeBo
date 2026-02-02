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
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var appRoute: AppRoute
    @EnvironmentObject var ledgerContext: LedgerContext
    @Environment(\.colorScheme) private var scheme
    @State private var showSettings = false
    
    var body: some View {
        Group {
            if ledgerContext.isRestored {
                TabView(selection: tabSelection) {
                    HomeView()
                        .tabItem { Label("ホーム", systemImage: "house.fill") }
                        .tag(AppRoute.Tab.home)
                    CalendarScreen()
                        .tabItem { Label("カレンダー", systemImage: "calendar") }
                        .tag(AppRoute.Tab.calendar)
                    ReportsView()
                        .tabItem { Label("レポート", systemImage: "chart.pie.fill") }
                        .tag(AppRoute.Tab.reports)
                    AllTransactionsView()
                        .tabItem { Label("履歴", systemImage: "magnifyingglass") }
                        .tag(AppRoute.Tab.history)
                    SettingsView()
                        .tabItem { Label("設定", systemImage: "gearshape.fill") }
                        .tag(AppRoute.Tab.settings)
                }
            } else {
                LedgerLoadingView()
            }
        }
        .toolbar(ledgerContext.isRestored ? .visible : .hidden, for: .tabBar)
        .overlay(TutorialGate())
        .overlay(UpdateNoticeGate())
        .overlay(NewYearReview2026Gate())
        .overlay(LoginMilestoneReviewGate())
        .overlay(alignment: .bottom) {
            SharedLedgerNotificationOverlay()
                .environmentObject(sharedLedgerStore)
                .allowsHitTesting(false)
        }
        .tint(themeStore.theme.accentColor(for: scheme))
    }

    private var tabSelection: Binding<AppRoute.Tab> {
        Binding(
            get: { appRoute.tab },
            set: { appRoute.tab = $0 }
        )
    }
}
