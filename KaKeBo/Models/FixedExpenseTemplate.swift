//
//  FixedExpenseTemplate.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/18.
//

import Foundation

/// 繰り返し終了条件
enum RepeatMode: Codable, Hashable, Equatable {
    /// 無制限（終了なし）
    case unlimited
    /// 指定回数で終了（例：12回）
    case count(Int)
    /// 指定日以降は計上しない
    case untilDate(Date)
}

/// 毎月の定額支出テンプレート（0 = 月末, 1...31）
struct FixedExpenseTemplate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String                  // 表示名（例：家賃）
    var amount: Int                    // 金額（正）
    var dayOfMonth: Int                // 0=月末, 1..31
    var categoryId: UUID               // 紐づけるカテゴリ（支出カテゴリ）
    var memo: String? = nil            // 任意メモ
    var isActive: Bool = true          // 有効/無効
    var tags: [String] = []            // 自動計上時に付与するタグ（最大8文字想定）
    var createdDate: Date = Date()     // 登録日
    var repeatMode: RepeatMode = .unlimited  // 繰り返し終了条件
    var appliedCount: Int = 0          // これまでに計上された回数

    init(id: UUID = UUID(),
         title: String,
         amount: Int,
         dayOfMonth: Int,
         categoryId: UUID,
         memo: String? = nil,
         isActive: Bool = true,
         tags: [String] = [],
         createdDate: Date = Date(),
         repeatMode: RepeatMode = .unlimited,
         appliedCount: Int = 0) {
        self.id = id
        self.title = title
        self.amount = amount
        self.dayOfMonth = dayOfMonth
        self.categoryId = categoryId
        self.memo = memo
        self.isActive = isActive
        self.tags = tags
        self.createdDate = createdDate
        self.repeatMode = repeatMode
        self.appliedCount = appliedCount
    }

    // 旧データとの互換用に手動デコード
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        amount = try container.decode(Int.self, forKey: .amount)
        dayOfMonth = try container.decode(Int.self, forKey: .dayOfMonth)
        categoryId = try container.decode(UUID.self, forKey: .categoryId)
        memo = try container.decodeIfPresent(String.self, forKey: .memo)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdDate = try container.decodeIfPresent(Date.self, forKey: .createdDate) ?? Date()
        repeatMode = try container.decodeIfPresent(RepeatMode.self, forKey: .repeatMode) ?? .unlimited
        appliedCount = try container.decodeIfPresent(Int.self, forKey: .appliedCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(amount, forKey: .amount)
        try container.encode(dayOfMonth, forKey: .dayOfMonth)
        try container.encode(categoryId, forKey: .categoryId)
        try container.encodeIfPresent(memo, forKey: .memo)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(tags, forKey: .tags)
        try container.encode(createdDate, forKey: .createdDate)
        try container.encode(repeatMode, forKey: .repeatMode)
        try container.encode(appliedCount, forKey: .appliedCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, dayOfMonth, categoryId, memo, isActive, tags
        case createdDate, repeatMode, appliedCount
    }

    /// 繰り返し上限に達しているか
    var isRepeatLimitReached: Bool {
        switch repeatMode {
        case .unlimited:
            return false
        case .count(let limit):
            return appliedCount >= limit
        case .untilDate(let endDate):
            return Date() > endDate
        }
    }

    /// 繰り返し状況のテキスト表示
    var repeatStatusText: String {
        switch repeatMode {
        case .unlimited:
            return appliedCount > 0 ? "\(appliedCount)回適用済み" : ""
        case .count(let limit):
            return "\(appliedCount)/\(limit)回"
        case .untilDate(let endDate):
            let f = DateFormatter()
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "yyyy/M/d"
            return "\(f.string(from: endDate))まで（\(appliedCount)回適用済み）"
        }
    }

    /// 登録からの経過月数
    var monthsSinceCreation: Int {
        let cal = Calendar.current
        let components = cal.dateComponents([.month], from: createdDate, to: Date())
        return max(0, components.month ?? 0)
    }
}
