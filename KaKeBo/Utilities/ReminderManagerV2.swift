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
    
    // MARK: - Public API (Viewから呼ばれるのはココだけでOK)
    
    /// 権限リクエスト（初回のみシステムUIが出る）
    @discardableResult
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            center.requestAuthorization(options: [.alert, .sound]) { ok, _ in
                cont.resume(returning: ok)
            }
        }
    }
    
    /// すべてのルールを再適用（削除→再登録）
    static func applyAll(rules: [ReminderRule], store: DataStore, todoStore: TodoStore) async {
        // 1) まず自分の名前空間の通知を一掃（pending + delivered）
        await removeAllOurRuleNotifications()
        // 2) レガシーの “monthly.*” を掃除（残って鳴る事故を防止）
        await sweepLegacyMonthly()
        // 3) 有効なルールだけ再登録
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
        await add([req])
    }
    
    // MARK: - Core
    
    private static func schedule(rule: ReminderRule, store: DataStore, todoStore: TodoStore) async {
        var reqs: [UNNotificationRequest] = []
        let hm = Calendar.current.dateComponents([.hour, .minute], from: rule.time)
        
        switch rule.repeatType {
        case .daily:
            var comps = DateComponents()
            comps.hour = hm.hour; comps.minute = hm.minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let content = content(for: rule, store: store, todoStore: todoStore)
            reqs.append(.init(identifier: id(for: rule), content: content, trigger: trigger))
            
        case .weekly:
            for w in rule.weekdays {
                var comps = DateComponents()
                comps.weekday = w
                comps.hour = hm.hour; comps.minute = hm.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let content = content(for: rule, store: store, todoStore: todoStore, weekday: w)
                reqs.append(.init(identifier: id(for: rule) + ".w\(w)", content: content, trigger: trigger))
            }
        }
        await add(reqs)
    }
    
    private static func content(for rule: ReminderRule, store: DataStore, todoStore: TodoStore, weekday: Int? = nil) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        
        // 条件用の簡易集計
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let hasUnlogged = store.transactions.first(where: { cal.isDate($0.date, inSameDayAs: today) }) == nil
        let todosToday = todoStore.todos.filter { $0.due.map{ cal.isDate($0, inSameDayAs: today) } ?? false && !$0.done }.count
        let isConditionMet = (!rule.onlyIfUnloggedToday || hasUnlogged)
            && (!rule.onlyIfTodosDueToday || todosToday > 0)
        
        let baseBodyTemplate: String
        if isConditionMet {
            baseBodyTemplate = rule.bodyTemplate
        } else {
            baseBodyTemplate = rule.fallbackBodyTemplate.isEmpty ? rule.bodyTemplate : rule.fallbackBodyTemplate
        }
        let body = resolveTemplate(baseBodyTemplate,
                                   todosToday: todosToday,
                                   hasUnlogged: hasUnlogged,
                                   date: today,
                                   weekdayOverride: weekday)
        let resolvedTitle = resolveTemplate(rule.title,
                                            todosToday: todosToday,
                                            hasUnlogged: hasUnlogged,
                                            date: today,
                                            weekdayOverride: weekday)
        
        c.title = resolvedTitle.isEmpty ? "KaKeBo" : resolvedTitle
        c.body = body
        if rule.soundEnabled { c.sound = .default }
        return c
    }

    private static func resolveTemplate(_ template: String,
                                        todosToday: Int,
                                        hasUnlogged: Bool,
                                        date: Date,
                                        weekdayOverride: Int? = nil) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "M/d"
        let weekdaySymbols = Calendar.current.shortStandaloneWeekdaySymbols
        let weekdayIndex = weekdayOverride ?? Calendar.current.component(.weekday, from: date)
        let weekdaySymbol = weekdaySymbols[(weekdayIndex - 1) % weekdaySymbols.count]
        return template
            .replacingOccurrences(of: ReminderPlaceholder.todosToday.rawValue, with: "\(todosToday)")
            .replacingOccurrences(of: ReminderPlaceholder.unloggedToday.rawValue, with: hasUnlogged ? "はい" : "いいえ")
            .replacingOccurrences(of: ReminderPlaceholder.todayDate.rawValue, with: dateFormatter.string(from: date))
            .replacingOccurrences(of: ReminderPlaceholder.todayWeekday.rawValue, with: weekdaySymbol)
    }
    
    // MARK: - Helpers
    
    private static func add(_ requests: [UNNotificationRequest]) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            for r in requests {
                group.enter()
                center.add(r) { _ in group.leave() }
            }
            group.notify(queue: .main) { cont.resume() }
        }
    }
    
    private static func pendingIds() async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            center.getPendingNotificationRequests { list in
                cont.resume(returning: list.map(\.identifier))
            }
        }
    }
    
    private static func deliveredIds(prefix: String) async -> [String] {
        await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            center.getDeliveredNotifications { delivered in
                let ids = delivered.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) }
                cont.resume(returning: ids)
            }
        }
    }
    
    private static func removeAllOurRuleNotifications() async {
        let prefix = "kakebo.rule."
        let p = await pendingIds().filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: p)
        let d = await deliveredIds(prefix: prefix)
        center.removeDeliveredNotifications(withIdentifiers: d)
    }
    
    /// 起動時などに呼ぶ公開掃除API：ルール未設定でも残ってしまうレガシーToDo通知を一掃する
    static func purgeLegacyTodoNotifications() async {
        await sweepLegacyMonthly()
    }

    /// レガシー掃除：かつての単発月次通知（monthly.*）を一掃して事故防止
    private static func sweepLegacyMonthly() async {
        let prefix = "monthly."
        let p = await pendingIds().filter { $0.hasPrefix(prefix) }
        if !p.isEmpty { center.removePendingNotificationRequests(withIdentifiers: p) }
        let d = await deliveredIds(prefix: prefix)
        if !d.isEmpty { center.removeDeliveredNotifications(withIdentifiers: d) }
    }
}
