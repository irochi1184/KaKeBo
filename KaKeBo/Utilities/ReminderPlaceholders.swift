//
//  Utilities/ReminderPlaceholders.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import Foundation

enum ReminderPlaceholder: String, CaseIterable, Identifiable {
    case todosToday     = "{todosToday}"     // 今日が期日の未完了ToDo件数
    //    case unloggedToday  = "{unloggedToday}"  // 今日の取引が未登録なら「はい」、登録済みなら「いいえ」
    
    var id: String { rawValue }
    
    var labelJP: String {
        switch self {
        case .todosToday:    return "今日のToDo件数"
            //        case .unloggedToday: return "今日の未登録"
        }
    }
    var hintJP: String {
        switch self {
        case .todosToday:    return "例）2（件数の数字）"
            //        case .unloggedToday: return "例）はい／いいえ"
        }
    }
}
