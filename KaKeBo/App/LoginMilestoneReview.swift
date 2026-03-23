import StoreKit
import SwiftUI
import UIKit

let totalday = 100

// MARK: - ログイン日数の集計
enum LoginDayTracker {
    private static let loginStartYear = 2026
    enum Keys {
        static let totalLoginDays = "engagement.login.totalDays"
        static let lastLoginDate = "engagement.login.lastDate"
    }

    /// 同じ日付での重複カウントを避けつつ、ログイン日数を+1する
    @discardableResult
    static func registerLogin(
        date: Date = Date(),
        defaults: UserDefaults = .appGroup,
        calendar: Calendar = .current
    ) -> Int {
        let loginYear = calendar.component(.year, from: date)
        if loginYear < loginStartYear {
            return defaults.integer(forKey: Keys.totalLoginDays)
        }

        let today = calendar.startOfDay(for: date)
        let lastInterval = defaults.double(forKey: Keys.lastLoginDate)

        if lastInterval > 0 {
            let lastDate = Date(timeIntervalSinceReferenceDate: lastInterval)
            if calendar.isDate(lastDate, inSameDayAs: today) {
                return defaults.integer(forKey: Keys.totalLoginDays)
            }
        }

        defaults.set(today.timeIntervalSinceReferenceDate, forKey: Keys.lastLoginDate)
        let newTotal = defaults.integer(forKey: Keys.totalLoginDays) + 1
        defaults.set(newTotal, forKey: Keys.totalLoginDays)
        return newTotal
    }
}

// MARK: - totalday日達成時のレビュー導線
struct LoginMilestoneReviewGate: View {
    @AppStorage(LoginDayTracker.Keys.totalLoginDays, store: .appGroup) private var totalLoginDays = 0
    @AppStorage("engagement.reviewPrompt.completed", store: .appGroup) private var reviewPromptCompleted = false

    @State private var isPresented = false

    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    private let calendar = Calendar.current

    private var accent: Color { themeStore.theme.accentColor(for: scheme) }
    private var background: Color { themeStore.theme.backgroundColor(for: scheme) }
    private var isNewYearGreeting: Bool {
        let today = Date()
        return calendar.component(.month, from: today) == 1
            && calendar.component(.day, from: today) == 1
    }

    var body: some View {
        LoginMilestoneReviewOverlay(
            isPresented: $isPresented,
            accent: accent,
            background: background,
            isNewYearGreeting: isNewYearGreeting
        )
            .onAppear { evaluateAndMaybeShow(registerLogin: true) }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    evaluateAndMaybeShow(registerLogin: true)
                }
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue == false && totalLoginDays >= totalday {
                    reviewPromptCompleted = true
                }
            }
    }

    private func evaluateAndMaybeShow(registerLogin: Bool) {
        if registerLogin {
            _ = LoginDayTracker.registerLogin()
        }

        if totalLoginDays >= totalday && !reviewPromptCompleted {
            isPresented = true
        }
    }
}

private struct LoginMilestoneReviewOverlay: View {
    @Binding var isPresented: Bool
    let accent: Color
    let background: Color
    let isNewYearGreeting: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if isPresented {
                background.opacity(scheme == .dark ? 0.9 : 0.85)
                    .ignoresSafeArea()

                content
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            message
            buttons
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.15), radius: 24, y: 12)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
                .padding(10)
                .background(Circle().fill(accent.opacity(0.15)))

            VStack(alignment: .leading, spacing: 4) {
                Text("おめでとうございます！")
                    .font(.title3.weight(.semibold))
                Text("累計\(totalday)日利用の達成です")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isNewYearGreeting {
                Text("明けましておめでとうございます！")
            }
            Text("あなたはこのアプリを使用して累計\(totalday)日が経過しました。")
            Text("\(totalday)日間、使い続けてくれてありがとうございます！")
            Text("この家計簿アプリは、\n「広告なしで、安心して使えるものを作りたい」\nという想いで、ひとりで開発・運営しています。")
            Text("正直、大きな収益はありません。\nそれでも続けられているのは、\n使ってくれている皆さんのおかげです。")
            Text("レビューでの応援が、\n次のアップデートの原動力になります。\nもし良ければレビューにご協力ください。")
        }
        .font(.body)
        .foregroundStyle(.primary)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: requestReview) {
                Text("はい")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)

            Button {
                isPresented = false
            } label: {
                Text("いいえ")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }

    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            isPresented = false
            return
        }
        
        SKStoreReviewController.requestReview(in: scene)
        isPresented = false
    }
}

@MainActor
final class ReviewRequestManager {
    static let shared = ReviewRequestManager()

    enum Keys {
        static let firstLaunchDate = "reviewRequest.firstLaunchDate"
        static let successfulSaveCount = "reviewRequest.successfulSaveCount"
        static let reportViewCount = "reviewRequest.reportViewCount"
        static let lastRequestAttemptDate = "reviewRequest.lastRequestAttemptDate"
        static let neverShowAgain = "reviewRequest.neverShowAgain"
    }

    enum Constants {
        static let minDaysSinceFirstLaunch = 3
        static let minSuccessfulSaveCount = 5
        static let minReportViewCount = 2
        static let requestCooldownDays = 30
        static let minDelaySeconds: ClosedRange<Double> = 0.8...1.5
    }

    private let defaults: UserDefaults
    private var hasAttemptedInSession = false
    private var delayedTask: Task<Void, Never>?

    private init() {
        self.defaults = .appGroup
        registerFirstLaunchIfNeeded()
    }

    func registerFirstLaunchIfNeeded(date: Date = Date()) {
        if defaults.object(forKey: Keys.firstLaunchDate) == nil {
            defaults.set(date, forKey: Keys.firstLaunchDate)
        }
    }

    func recordSuccessfulSave() {
        let next = defaults.integer(forKey: Keys.successfulSaveCount) + 1
        defaults.set(next, forKey: Keys.successfulSaveCount)
    }

    func recordReportScreenViewed() {
        let next = defaults.integer(forKey: Keys.reportViewCount) + 1
        defaults.set(next, forKey: Keys.reportViewCount)
    }

    func scheduleReviewRequestIfEligible() {
        delayedTask?.cancel()
        delayedTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let delay = Double.random(in: Constants.minDelaySeconds)
            let delayNanos = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delayNanos)
            self.tryPresentReviewPrompt()
        }
    }

    private func tryPresentReviewPrompt(now: Date = Date()) {
        guard isEligible(now: now) else { return }
        guard let scene = activeWindowScene() else { return }
        guard let topVC = topViewController(in: scene) else { return }

        hasAttemptedInSession = true
        defaults.set(now, forKey: Keys.lastRequestAttemptDate)

        let alert = UIAlertController(
            title: "KaKeBoをご利用いただきありがとうございます",
            message: "使い心地はいかがですか？よろしければレビューで応援していただけると励みになります。",
            preferredStyle: .alert
        )

        alert.addAction(UIAlertAction(title: "今回はしない", style: .cancel))
        alert.addAction(UIAlertAction(title: "今後表示しない", style: .destructive) { [weak self] _ in
            self?.defaults.set(true, forKey: Keys.neverShowAgain)
        })
        alert.addAction(UIAlertAction(title: "レビューする", style: .default) { _ in
            SKStoreReviewController.requestReview(in: scene)
        })

        topVC.present(alert, animated: true)
    }

    private func isEligible(now: Date) -> Bool {
        if hasAttemptedInSession { return false }
        if defaults.bool(forKey: Keys.neverShowAgain) { return false }

        guard let firstLaunch = defaults.object(forKey: Keys.firstLaunchDate) as? Date else {
            return false
        }

        let calendar = Calendar.current
        guard let launchThreshold = calendar.date(byAdding: .day, value: Constants.minDaysSinceFirstLaunch, to: firstLaunch),
              now >= launchThreshold else {
            return false
        }

        let successfulSaveCount = defaults.integer(forKey: Keys.successfulSaveCount)
        guard successfulSaveCount >= Constants.minSuccessfulSaveCount else {
            return false
        }

        let reportViewCount = defaults.integer(forKey: Keys.reportViewCount)
        guard reportViewCount >= Constants.minReportViewCount else {
            return false
        }

        if let lastAttempt = defaults.object(forKey: Keys.lastRequestAttemptDate) as? Date,
           let nextAvailable = calendar.date(byAdding: .day, value: Constants.requestCooldownDays, to: lastAttempt),
           now < nextAvailable {
            return false
        }

        return true
    }

    private func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
    }

    private func topViewController(in scene: UIWindowScene) -> UIViewController? {
        guard let window = scene.windows.first(where: \.isKeyWindow),
              window.isHidden == false,
              let root = window.rootViewController else {
            return nil
        }

        // シートやフルスクリーンなど、すでにモーダルが出ている場合は表示しない
        if root.presentedViewController != nil {
            return nil
        }

        var top = root
        while let presented = top.presentedViewController {
            top = presented
        }

        if top.isBeingDismissed || top.isBeingPresented {
            return nil
        }
        if top.transitionCoordinator != nil {
            return nil
        }

        return top
    }
}
