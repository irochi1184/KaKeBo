//
//  Models/ReminderRule.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import Foundation

enum ReminderRepeat: String, Codable, CaseIterable, Identifiable {
    case daily, weekly
    var id: String { rawValue }
}

struct ReminderRule: Identifiable, Codable, Equatable {
    var id: UUID = .init()
    var enabled: Bool = true
    
    // スケジュール
    var repeatType: ReminderRepeat = .daily
    var time: Date = Calendar.current.date(from: DateComponents(hour: 21, minute: 0)) ?? Date()
    /// weekly の場合のみ使用（日=1 ... 土=7）
    var weekdays: Set<Int> = [2,3,4,5,6] // 既定: 平日
    
    // 通知内容
    var title: String = "家計簿の記録をお忘れなく"
    /// 簡易テンプレ: {todosToday}, {unloggedToday}
    var bodyTemplate: String = "今日の支出・収入をサクッと登録しましょう。残りToDo: {todosToday}"
    /// 条件未達時に使う本文テンプレ（空なら通常本文を使う）
    var fallbackBodyTemplate: String = "進捗チェック：条件に一致しないため通知のみ表示しています。"
    
    // 条件
    var onlyIfUnloggedToday: Bool = false       // まだ今日の取引が0件のときだけ
    var onlyIfTodosDueToday: Bool = false       // 今日が期日のToDoが1件以上あるとき
    var soundEnabled: Bool = true
    
    // 並び順
    var sortOrder: Int = 0
}
