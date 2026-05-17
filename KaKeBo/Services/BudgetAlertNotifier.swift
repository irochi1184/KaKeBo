import Foundation
import UserNotifications

/// 予算超過が見込まれる場合にローカル通知を送信する
enum BudgetAlertNotifier {
    private static let notificationId = "kakebo.budget.alert"
    /// 1日1回だけ通知するためのキー
    private static let lastAlertDateKey = "kakebo.budget.lastAlertDate"

    /// 予測結果に基づいて予算超過通知を送信する（1日1回制限）
    static func checkAndNotify(forecast: BudgetForecastService.Forecast) {
        guard forecast.isOverBudget, forecast.overBudgetAmount > 0 else { return }
        guard shouldNotifyToday() else { return }

        let content = UNMutableNotificationContent()
        content.title = "予算超過の見込み"

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        let overAmount = "¥" + (formatter.string(from: forecast.overBudgetAmount as NSNumber) ?? "\(forecast.overBudgetAmount)")
        let projected = "¥" + (formatter.string(from: forecast.projectedExpense as NSNumber) ?? "\(forecast.projectedExpense)")

        content.body = "今月の支出は\(projected)に達する見込みです（\(overAmount)超過）。"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        let request = UNNotificationRequest(identifier: notificationId, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { _ in }
        markNotifiedToday()
    }

    private static func shouldNotifyToday() -> Bool {
        let defaults = UserDefaults.appGroup
        guard let lastDate = defaults.object(forKey: lastAlertDateKey) as? Date else { return true }
        return !Calendar.current.isDateInToday(lastDate)
    }

    private static func markNotifiedToday() {
        UserDefaults.appGroup.set(Date(), forKey: lastAlertDateKey)
    }
}
