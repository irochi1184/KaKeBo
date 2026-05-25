//
//  WatchModels.swift
//  KaKeBoWatch
//
//  Watch側で使用する軽量データモデル
//

import Foundation

/// よく使うテンプレート（Watch向け軽量版）
struct WatchTemplate: Identifiable, Codable {
    let id: UUID
    let title: String
    let amount: Int
    let type: String // "expense" or "income"
    let memo: String
    let categoryId: UUID
    let categoryName: String
    let categorySymbol: String
    let categoryColorHex: String
    let tags: [String]
}

/// カテゴリ（Watch向け軽量版）
struct WatchCategory: Identifiable, Codable {
    let id: UUID
    let name: String
    let symbolName: String
    let colorHex: String
}
