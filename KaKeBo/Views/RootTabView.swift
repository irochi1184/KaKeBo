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
    @State private var showLaunchScreen = true

    private let launchScreenMinDuration: UInt64 = 600_000_000
    
    var body: some View {
        ZStack {
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
            .opacity(showLaunchScreen ? 0 : 1)
            .allowsHitTesting(!showLaunchScreen)

            if showLaunchScreen {
                LedgerLoadingView()
                    .transition(.opacity)
            }
        }
        .task { await startLaunchSequence() }
        .toolbar(showLaunchScreen ? .hidden : .visible, for: .tabBar)
        .overlay(TutorialGate())
        .overlay(UpdateNoticeGate())
        .overlay(LoginMilestoneReviewGate())
        .overlay(alignment: .bottom) {
            SharedLedgerNotificationOverlay()
                .environmentObject(sharedLedgerStore)
        }
        .environment(\.appVisualStyle, themeStore.theme.visualStyle)
        .environment(\.appHomeCardStyle, themeStore.theme.homeCardStyle)
        .environment(\.appIncomeColor, themeStore.theme.transactionColor(isIncome: true))
        .environment(\.appExpenseColor, themeStore.theme.transactionColor(isIncome: false))
        .modifier(AppFontModifier(fontFamily: themeStore.theme.resolvedFontFamily))
        .tint(themeStore.theme.accentColor(for: scheme))
    }

    private var tabSelection: Binding<AppRoute.Tab> {
        Binding(
            get: { appRoute.tab },
            set: { appRoute.tab = $0 }
        )
    }

    private func startLaunchSequence() async {
        if ledgerContext.isRestored {
            showLaunchScreen = false
            return
        }

        async let restoreTask: Void = ledgerContext.restoreIfNeeded(sharedLedgerStore: sharedLedgerStore)

        do {
            try await Task.sleep(nanoseconds: launchScreenMinDuration)
        } catch {
            // ignore cancellation
        }

        withAnimation(.easeOut(duration: 0.2)) {
            showLaunchScreen = false
        }

        _ = await restoreTask
    }
}
