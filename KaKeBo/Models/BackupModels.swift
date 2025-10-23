//
//  Models/BackupModels.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/23.
//

import SwiftUI
import UniformTypeIdentifiers

// v1 スキーマ（将来の拡張に備えて version を持たせる）
struct KaKeBoBackupV1: Codable {
    var version: Int = 1
    let exportedAt: Date
    // 必須
    var categories: [BackupCategory]
    var transactions: [BackupTransaction]
    // 任意（あるなら完全復元）
    var recurringTodos: [BackupRecurringTodo]?
    var fixedExpenses: [BackupFixedExpense]?
    var reminders: [BackupReminderRule]?
    var theme: BackupTheme?
}

struct BackupCategory: Codable, Identifiable {
    var id: UUID
    var name: String
    var symbolName: String
    var colorHex: String // "#RRGGBBAA"
}

struct BackupTransaction: Codable, Identifiable {
    var id: UUID
    var date: Date
    var amount: Int
    var typeRaw: String   // "income" | "expense"
    var memo: String
    var categoryId: UUID
}

// ここはアプリの実体に合わせて最低限（あれば復元）
struct BackupRecurringTodo: Codable, Identifiable {
    var id: UUID
    var title: String
    var dayOfMonth: Int  // 0=月末 など、あなたの実装に合わせて
    var isActive: Bool
}

struct BackupFixedExpense: Codable, Identifiable {
    var id: UUID
    var title: String
    var amount: Int
    var dayOfMonth: Int
    var categoryId: UUID?
    var memo: String
    var isActive: Bool
}

struct BackupReminderRule: Codable, Identifiable {
    var id: UUID
    var enabled: Bool
    var hour: Int
    var minute: Int
    // 条件等があれば拡張
}

struct BackupTheme: Codable {
    // プリセット/カスタムを完全復元
    var activePresetRaw: String        // "default" "green" "red" "orange" "custom"
    var useSameAccentForBoth: Bool
    var accentLightHex: String
    var accentDarkHex: String
    var useSameBackgroundForBoth: Bool
    var backgroundLightHex: String
    var backgroundDarkHex: String
}

extension UTType {
    static let kakeboBackup = UTType(exportedAs: "com.irochi.kakebo.backup",
                                     conformingTo: .json)
}

