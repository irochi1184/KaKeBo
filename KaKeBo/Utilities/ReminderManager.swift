//
//  Utilities/ReminderManager.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/22.
//

import Foundation
import UserNotifications

enum ReminderManager {
    static let dailyId = "daily.reminder.kakebo"
    
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            return granted
        } catch {
            print("Notif auth error:", error)
            return false
        }
    }
    
    static func scheduleDaily(hour: Int, minute: Int, body: String = "今日の出費を記録しましょう") async {
        await cancel(id: dailyId)
        
        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        
        let content = UNMutableNotificationContent()
        content.title = "KaKeBo リマインダー"
        content.body = body
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let req = UNNotificationRequest(identifier: dailyId, content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(req)
        } catch {
            print("schedule error:", error)
        }
    }
    
    static func cancel(id: String) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }
}
