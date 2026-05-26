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
    var frequentTransactions: [BackupFrequentTransaction]? = nil
    var reminders: [BackupReminderRule]?
    var dayNotes: [BackupDayNote]?
    var monthStartSettings: BackupMonthStartSettings?
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
    var tags: [String]?
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
    // v2.3.4 で追加（旧バックアップとの互換性のためオプショナル）
    var tags: [String]?
    var createdDate: Date?
    var repeatMode: RepeatMode?
    var appliedCount: Int?
}

struct BackupFrequentTransaction: Codable, Identifiable {
    var id: UUID
    var title: String
    var amount: Int
    var typeRaw: String   // "income" | "expense"
    var memo: String
    var categoryId: UUID
    var tags: [String]
}

struct BackupReminderRule: Codable, Identifiable {
    var id: UUID
    var enabled: Bool
    var hour: Int
    var minute: Int
    // 条件等があれば拡張
}

struct BackupDayNote: Codable, Identifiable {
    var id: String { dateKey }
    /// "yyyy-MM-dd" 形式
    var dateKey: String
    var text: String
}

struct BackupMonthStartSettings: Codable {
    var isCustomStartEnabled: Bool
    var boundaryTypeRaw: String
    var startDay: Int
    var holidayAdjustmentRaw: String
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
    // 電卓キーパッドカラー
    var keypadIncomeHex: String?
    var keypadExpenseHex: String?
    // 収支表示カラー
    var incomeHex: String?
    var expenseHex: String?
    // カードスタイル・ビジュアルスタイル
    var homeCardStyleRaw: String?
    var visualStyleRaw: String?
    // 電卓設定
    var prefersCustomKeypad: Bool?
}

extension UTType {
    static let kakeboBackup = UTType(importedAs: "com.irochi.kakebo.backup",
                                     conformingTo: .json)
    static let kakeboClearDrop = UTType(exportedAs: "com.irochi.kakebo.clear-drop")
}
