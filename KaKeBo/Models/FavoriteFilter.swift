//
//  Models/FavoriteFilter.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2026/05/27.
//

import Foundation

/// 保存された絞り込み条件
struct FavoriteFilter: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var createdAt: Date = Date()

    // 種別
    var transactionTypeRaw: String?  // "income" | "expense" | nil(すべて)

    // カテゴリ
    var categoryIDs: [UUID] = []

    // タグ
    var tags: [String] = []

    // 金額範囲
    var minAmount: Int?
    var maxAmount: Int?

    // 並び替え
    var sortRaw: String = "dateDesc"

    // 期間は保存しない（日付は毎回変わるため実用的でない）

    /// フィルター条件の概要テキスト
    func summaryText(categories: [Category]) -> String {
        var parts: [String] = []
        if let raw = transactionTypeRaw {
            parts.append(raw == "income" ? "収入" : "支出")
        }
        if !categoryIDs.isEmpty {
            let names = categoryIDs.compactMap { id in
                categories.first(where: { $0.id == id })?.name
            }
            if names.count <= 2 {
                parts.append(names.joined(separator: "・"))
            } else {
                parts.append("\(names[0])ほか\(names.count - 1)件")
            }
        }
        if !tags.isEmpty {
            parts.append("タグ\(tags.count)件")
        }
        if minAmount != nil || maxAmount != nil {
            let lo = minAmount.map { "¥\($0)" } ?? ""
            let hi = maxAmount.map { "¥\($0)" } ?? ""
            if !lo.isEmpty && !hi.isEmpty {
                parts.append("\(lo)〜\(hi)")
            } else if !lo.isEmpty {
                parts.append("\(lo)以上")
            } else {
                parts.append("\(hi)以下")
            }
        }
        return parts.isEmpty ? "条件なし" : parts.joined(separator: " / ")
    }
}

// MARK: - 保存・読み込み

extension FavoriteFilter {
    private static let storageKey = "kakebo.favoriteFilters"

    static func loadAll() -> [FavoriteFilter] {
        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: [storageKey])
        guard let data = defaults.migratedData(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([FavoriteFilter].self, from: data)) ?? []
    }

    static func saveAll(_ filters: [FavoriteFilter]) {
        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: [storageKey])
        defaults.set(try? JSONEncoder().encode(filters), forKey: storageKey)
    }
}
