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
}
