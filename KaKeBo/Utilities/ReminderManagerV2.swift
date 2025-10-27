//
//  Utilities/ReminderManagerV2.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import Foundation
import UserNotifications
import SwiftUI

enum ReminderManagerV2 {
    private static let center = UNUserNotificationCenter.current()
    private static func id(for rule: ReminderRule) -> String { "kakebo.rule.\(rule.id.uuidString)" }
    
    /// すべてのルールを再適用（削除→再登録）
    static func applyAll(rules: [ReminderRule], store: DataStore, todoStore: TodoStore) async {
        // まず、この名前空間の通知を一掃
        let pending = await pendingIds()
        let ours = pending.filter { $0.hasPrefix("kakebo.rule.") }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        
        for rule in rules where rule.enabled {
            await schedule(rule: rule, store: store, todoStore: todoStore)
        }
    }
    
    /// テスト送信（即時1回）
    static func fireTest(rule: ReminderRule, store: DataStore, todoStore: TodoStore) async {
        let id = id(for: rule) + ".test.\(UUID().uuidString.prefix(6))"
        let content = content(for: rule, store: store, todoStore: todoStore)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1.0, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            center.add(req) { _ in cont.resume() }
        }
    }
    
    private static func schedule(rule: ReminderRule, store: DataStore, todoStore: TodoStore) async {
        var reqs: [UNNotificationRequest] = []
        
        switch rule.repeatType {
        case .daily:
            var comps = DateComponents()
            let hm = Calendar.current.dateComponents([.hour, .minute], from: rule.time)
            comps.hour = hm.hour; comps.minute = hm.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let content = content(for: rule, store: store, todoStore: todoStore)
            reqs.append(.init(identifier: id(for: rule), content: content, trigger: trigger))
            
        case .weekly:
            let hm = Calendar.current.dateComponents([.hour, .minute], from: rule.time)
            for w in rule.weekdays {
                var comps = DateComponents()
                comps.weekday = w
                comps.hour = hm.hour; comps.minute = hm.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let content = content(for: rule, store: store, todoStore: todoStore, weekday: w)
                reqs.append(.init(identifier: id(for: rule) + ".w\(w)", content: content, trigger: trigger))
            }
        }
        
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for r in reqs {
                group.enter()
                center.add(r) { _ in group.leave() }
            }
            group.notify(queue: .main) { cont.resume() }
        }
    }
    
    private static func content(for rule: ReminderRule, store: DataStore, todoStore: TodoStore, weekday: Int? = nil) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = rule.title
        
        // 条件用の簡易集計
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let hasUnlogged = store.transactions.first(where: { cal.isDate($0.date, inSameDayAs: today) }) == nil
        let todosToday = todoStore.todos.filter { $0.due.map{ cal.isDate($0, inSameDayAs: today) } ?? false && !$0.done }.count
        
        // 条件 → 片方でも成り立たない & フィルタ指定がある場合は内容を「条件未達の軽い促し」に変更（通知自体の抑制は iOS では難しい）
        var body = rule.bodyTemplate
            .replacingOccurrences(of: "{todosToday}", with: "\(todosToday)")
            .replacingOccurrences(of: "{unloggedToday}", with: hasUnlogged ? "はい" : "いいえ")
        
        if (rule.onlyIfUnloggedToday && !hasUnlogged) ||
            (rule.onlyIfTodosDueToday && todosToday == 0) {
            body = "進捗チェック：条件に一致しないため、通知のみ表示しています。"
        }
        
        c.body = body
        if rule.soundEnabled { c.sound = .default }
        return c
    }
    
    private static func pendingIds() async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            center.getPendingNotificationRequests { list in
                cont.resume(returning: list.map(\.identifier))
            }
        }
    }
}
