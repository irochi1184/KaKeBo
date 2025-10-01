//
//  Models/CalendarTodo.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/30.
//

import Foundation

struct CalendarTodo: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var done: Bool = false
    var due: Date?
    var templateId: UUID? = nil
}
