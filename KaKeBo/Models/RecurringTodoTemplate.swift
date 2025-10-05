//
//  RecurringTodoTemplate.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/01.
//

import Foundation

struct RecurringTodoTemplate: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// 1〜31 or 0=月末（30日の月は30日、2月は月末などに自動調整）
    var dayOfMonth: Int
    /// その月に展開する/しないの切替（将来の一時停止用）
    var isActive: Bool = true
    
    var defaultCategoryId: UUID? = nil
    var defaultAmount: Int? = nil
    var defaultMemo: String? = nil
}
