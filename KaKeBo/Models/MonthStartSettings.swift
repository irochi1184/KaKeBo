//
//  Models/MonthStartSettings.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/02/23.
//

import Foundation

/// 月の開始日に関する設定情報
struct MonthStartSettings: Codable, Equatable {
    /// カスタム開始日を有効にするかどうか
    var isCustomStartEnabled: Bool
    /// 月の開始日にしたい日付（1〜31の範囲で保持し、実際には月末日でクランプする）
    var startDay: Int
    /// 休日・週末に当たった場合の調整方法
    var holidayAdjustment: MonthStartAdjustment

    static let `default` = MonthStartSettings(isCustomStartEnabled: false,
                                              startDay: 1,
                                              holidayAdjustment: .none)
}

/// 土日祝日に当たった時の調整方法
enum MonthStartAdjustment: String, Codable, CaseIterable, Identifiable {
    case none
    case previousWeekday
    case nextWeekday

    var id: String { rawValue }

    /// 表示用の説明
    var label: String {
        switch self {
        case .none: return "そのまま"
        case .previousWeekday: return "直前の平日にする"
        case .nextWeekday: return "直後の平日にする"
        }
    }
}
