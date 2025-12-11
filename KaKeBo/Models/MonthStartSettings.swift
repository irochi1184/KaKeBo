//
//  Models/MonthStartSettings.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/12/08.
//

import Foundation

/// 月の開始日に関する設定情報
struct MonthStartSettings: Codable, Equatable {
    /// カスタム開始日を有効にするかどうか
    var isCustomStartEnabled: Bool
    /// 指定する日付を「開始日」として使うか「締め日」として使うか
    var boundaryType: MonthBoundaryType
    /// 月の開始日にしたい日付（1〜31の範囲で保持し、実際には月末日でクランプする）
    var startDay: Int
    /// 休日・週末に当たった場合の調整方法
    var holidayAdjustment: MonthStartAdjustment

    static let `default` = MonthStartSettings(isCustomStartEnabled: false,
                                              boundaryType: .startDay,
                                              startDay: 1,
                                              holidayAdjustment: .none)

    enum CodingKeys: String, CodingKey {
        case isCustomStartEnabled
        case boundaryType
        case startDay
        case holidayAdjustment
    }

    init(isCustomStartEnabled: Bool,
         boundaryType: MonthBoundaryType,
         startDay: Int,
         holidayAdjustment: MonthStartAdjustment) {
        self.isCustomStartEnabled = isCustomStartEnabled
        self.boundaryType = boundaryType
        self.startDay = startDay
        self.holidayAdjustment = holidayAdjustment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isCustomStartEnabled = try container.decode(Bool.self, forKey: .isCustomStartEnabled)
        boundaryType = try container.decodeIfPresent(MonthBoundaryType.self, forKey: .boundaryType) ?? .startDay
        startDay = try container.decode(Int.self, forKey: .startDay)
        holidayAdjustment = try container.decode(MonthStartAdjustment.self, forKey: .holidayAdjustment)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isCustomStartEnabled, forKey: .isCustomStartEnabled)
        try container.encode(boundaryType, forKey: .boundaryType)
        try container.encode(startDay, forKey: .startDay)
        try container.encode(holidayAdjustment, forKey: .holidayAdjustment)
    }
}

/// 「開始日」／「締め日」のどちらとして扱うか
enum MonthBoundaryType: String, Codable, CaseIterable, Identifiable {
    case startDay
    case endDay

    var id: String { rawValue }

    var label: String {
        switch self {
        case .startDay: return "開始日として使う"
        case .endDay: return "締め日として使う"
        }
    }
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
        case .previousWeekday: return "直前の平日"
        case .nextWeekday: return "直後の平日"
        }
    }
}
