//
//  FixedExpenseTemplate.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/18.
//

import Foundation

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

    init(id: UUID = UUID(),
         title: String,
         amount: Int,
         dayOfMonth: Int,
         categoryId: UUID,
         memo: String? = nil,
         isActive: Bool = true,
         tags: [String] = []) {
        self.id = id
        self.title = title
        self.amount = amount
        self.dayOfMonth = dayOfMonth
        self.categoryId = categoryId
        self.memo = memo
        self.isActive = isActive
        self.tags = tags
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
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, amount, dayOfMonth, categoryId, memo, isActive, tags
    }
}
