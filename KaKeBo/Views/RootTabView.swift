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
    @State private var didApplyLaunchScreenOption = false

    private let launchScreenMinDuration: UInt64 = 600_000_000  // 0.6秒
    private let launchScreenTimeout: UInt64 = 5_000_000_000    // 5秒タイムアウト
    
    var body: some View {
        ZStack {
            TabView(selection: tabSelection) {
                HomeView(showSideMenu: $showSettings)
                    .tabItem { Label("ホーム", systemImage: "house.fill") }
                    .tag(AppRoute.Tab.home)
                CalendarScreen(showSideMenu: $showSettings)
                    .tabItem { Label("カレンダー", systemImage: "calendar") }
                    .tag(AppRoute.Tab.calendar)
                ReportsView(showSideMenu: $showSettings)
                    .tabItem { Label("レポート", systemImage: "chart.pie.fill") }
                    .tag(AppRoute.Tab.reports)
                AllTransactionsView(showSideMenu: $showSettings)
                    .tabItem { Label("履歴", systemImage: "magnifyingglass") }
                    .tag(AppRoute.Tab.history)
                BudgetTabView(showSideMenu: $showSettings)
                    .tabItem { Label("予算", systemImage: "yensign.circle") }
                    .tag(AppRoute.Tab.budget)
            }
            .opacity(showLaunchScreen ? 0 : 1)
            .allowsHitTesting(!showLaunchScreen)

            if showLaunchScreen {
                LedgerLoadingView()
                    .transition(.opacity)
            }

            // サイドメニュー
            SideMenuView(isOpen: $showSettings)
                .allowsHitTesting(showSettings)
        }
        .task { await startLaunchSequence() }
        .toolbar(showLaunchScreen ? .hidden : .visible, for: .tabBar)
        // 起動時に開く画面の「取引追加」用シート（初回選択画面からの即時反映にも使用）
        .sheet(isPresented: $appRoute.addTransactionRequested) {
            AddTransactionView(defaultCategoryId: store.categories.first?.id)
                .environmentObject(store)
                .environmentObject(themeStore)
                .environmentObject(sharedLedgerStore)
                .environmentObject(ledgerContext)
        }
        .overlay(TutorialGate())
        .overlay(UpdateNoticeGate())
        .overlay(LaunchScreenPromptGate())
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

    /// 設定「起動時に開く画面」を適用する。ウィジェット等のディープリンクが先に来ていればそちらを優先。
    /// 戻り値は取引追加シートを開くべきかどうか。
    private func applyLaunchScreenOptionIfNeeded() -> Bool {
        guard !didApplyLaunchScreenOption else { return false }
        didApplyLaunchScreenOption = true
        guard !appRoute.didHandleDeepLink else { return false }

        let option = LaunchScreenOption.loadFromDefaults()
        appRoute.tab = option.tab
        return option == .addTransaction
    }

    /// 起動画面のフェード後に取引追加シートを開く
    private func presentLaunchAddTransaction() async {
        try? await Task.sleep(nanoseconds: 300_000_000)
        // シート表示の直前にもディープリンク割り込みを確認する
        if !appRoute.didHandleDeepLink {
            appRoute.addTransactionRequested = true
        }
    }

    private func startLaunchSequence() async {
        let shouldPresentAdd = applyLaunchScreenOptionIfNeeded()

        if ledgerContext.isRestored {
            withAnimation(.easeOut(duration: 0.2)) {
                showLaunchScreen = false
            }
            if shouldPresentAdd {
                await presentLaunchAddTransaction()
            }
            return
        }

        // 最小表示時間と復元処理を並行実行し、両方の完了を待つ
        // ただしタイムアウトを設け、CloudKit 障害時でも必ず画面を表示する
        await withTaskGroup(of: Void.self) { group in
            // 復元処理（タイムアウト付き）
            group.addTask {
                await withTaskGroup(of: Void.self) { inner in
                    inner.addTask {
                        await ledgerContext.restoreIfNeeded(sharedLedgerStore: sharedLedgerStore)
                    }
                    inner.addTask {
                        try? await Task.sleep(nanoseconds: launchScreenTimeout)
                        // タイムアウト到達時、まだ復元が終わっていなければ強制完了
                        if await !ledgerContext.isRestored {
                            await MainActor.run {
                                ledgerContext.forceRestoreAsPersonal()
                            }
                            #if DEBUG
                            print("⚠️ [RootTabView] 起動タイムアウト: 個人モードにフォールバック")
                            #endif
                        }
                    }
                    // どちらか先に終わったら完了
                    for await _ in inner.prefix(1) { }
                    inner.cancelAll()
                }
            }

            // 最小表示時間
            group.addTask {
                try? await Task.sleep(nanoseconds: launchScreenMinDuration)
            }

            // 両方完了を待つ
            for await _ in group { }
        }

        withAnimation(.easeOut(duration: 0.2)) {
            showLaunchScreen = false
        }

        #if DEBUG
        print("✅ [RootTabView] 起動シーケンス完了 mode=\(ledgerContext.mode)")
        #endif

        if shouldPresentAdd {
            await presentLaunchAddTransaction()
        }
    }
}
