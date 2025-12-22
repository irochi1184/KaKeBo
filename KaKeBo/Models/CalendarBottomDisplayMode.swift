//
//  Models/CalendarBottomDisplayMode.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/10/19.
//

import Foundation

enum CalendarBottomDisplayMode: String, CaseIterable, Identifiable {
    case monthTodo
    case dayDetail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthTodo:
            return "選択月のToDo"
        case .dayDetail:
            return "選択日の詳細"
        }
    }

    var description: String {
        switch self {
        case .monthTodo:
            return "選択月のToDo一覧を表示します（従来の表示）。"
        case .dayDetail:
            return "今日の取引・ToDo・メモを表示し、日付を選ぶと下部が切り替わります。"
        }
    }
}
