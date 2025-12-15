//
//  SampleBackupGenerator.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/23.
//

import Foundation
import SwiftUI

// 既存のバックアップ用モデル（あなたのプロジェクトにある）をそのまま使います。
// - KaKeBoBackupV1
// - BackupCategory
// - BackupTransaction
// - BackupRecurringTodo
// - BackupTheme
// - colorToHex / hexToColor があるなら不要ですが、この関数では使いません。

/// App 内へ流し込める 2025 年のサンプル完全バックアップ JSON を生成
/// - Returns: KaKeBoBackupV1 を ISO8601 でエンコードした Data
func makeSample2025BackupJSON() -> Data {
    // ===== カテゴリ（ユーザーが提示した ID とアイコン/色を流用） =====
    // ※ この ID をトランザクションで参照するので変更しないでください。
    let catFood      = UUID(uuidString: "E2FDA9C7-763D-4E81-B2F1-1DBBF37C2FD1")! // 食費
    let catComms     = UUID(uuidString: "CA517276-BAC2-46E9-8001-EA4CD5B54E34")! // 通信料（サブスク等）
    let catKousai    = UUID(uuidString: "270094F9-4687-43CC-AB4E-1F0814A22F33")! // 交際費（今回は未使用）
    let catOtherInc  = UUID(uuidString: "EC384237-B060-4E09-91D6-79505CC3FB34")! // その他収入（未使用）
    let catUtility   = UUID(uuidString: "9A4A964D-1E3A-48F9-94B0-825F9D6EA6E1")! // 水道光熱費
    let catTransport = UUID(uuidString: "BC9D5A7F-916B-4E64-AC68-6216963D2700")! // 交通費
    let catRent      = UUID(uuidString: "CB2983DE-40E2-49DB-99D5-BFA0F83F4985")! // 住宅費（家賃）
    let catMedical   = UUID(uuidString: "3BD3F354-BAE8-43CA-A16D-71490B170BDC")! // 医療費
    let catLeisure   = UUID(uuidString: "B1670827-DCB9-4128-869E-5DCA44DF7426")! // 娯楽費
    let catSalary    = UUID(uuidString: "09F21E99-45D9-4FE1-866B-A9AF37405D2C")! // 給与
    let catDaily     = UUID(uuidString: "1D5A9ADE-8567-49BA-960F-725CA490B299")! // 日用品費
    
    let categories: [BackupCategory] = [
        .init(id: catFood,      name: "食費",     symbolName: "fork.knife",          colorHex: "#F54D5BFF"),
        .init(id: catComms,     name: "通信料",   symbolName: "wifi",                colorHex: "#9C87FFFF"),
        .init(id: catKousai,    name: "交際費",   symbolName: "gift.fill",           colorHex: "#00DAC3FF"),
        .init(id: catOtherInc,  name: "その他収入", symbolName: "yensign.circle.fill", colorHex: "#3CD3FEFF"),
        .init(id: catUtility,   name: "水道光熱費", symbolName: "lightbulb.fill",      colorHex: "#00DFFFFF"),
        .init(id: catTransport, name: "交通費",   symbolName: "tram.fill",           colorHex: "#7187A2FF"),
        .init(id: catRent,      name: "住宅費",   symbolName: "house.fill",          colorHex: "#AC674CFF"),
        .init(id: catMedical,   name: "医療費",   symbolName: "cross.case.fill",     colorHex: "#CC3D8BFF"),
        .init(id: catLeisure,   name: "娯楽費",   symbolName: "gamecontroller.fill", colorHex: "#00B11FFF"),
        .init(id: catSalary,    name: "給与",     symbolName: "yensign.circle",      colorHex: "#1B8776FF"),
        .init(id: catDaily,     name: "日用品費", symbolName: "bag.fill",            colorHex: "#FFBF5EFF")
    ]

    
    // ===== 1年分の金額パラメータ（各月で合計 140,000〜200,000 円）=====
    // 食費（各月 30,000〜60,000）
    let food: [Int] = [45000, 38000, 52000, 41000, 50000, 33000, 47000, 36000, 54000, 42000, 50000, 35000]
    // 光熱費（12,000〜16,500）
    let utility: [Int] = [15000, 13000, 16000, 14000, 15000, 12000, 15000, 13500, 16500, 14500, 15000, 12500]
    // 交通費（5,000〜9,500）
    let transport: [Int] = [8000, 6000, 9000, 7000, 8000, 5000, 8500, 6500, 9500, 7500, 8000, 5500]
    // 娯楽（3,000〜10,000）※範囲内で調整済み
    let leisure: [Int]   = [7000, 5000, 6000, 4000, 7000, 3000, 8000, 6000, 7000, 5000, 8000, 4000]
    // 日用品（6,500〜14,000）※一部月で合計調整
    var daily: [Int] = [12000, 8000, 6500, 11500, 9500, 9000, 10500, 11000, 2000, 9000, 8500, 10000]
    // 医療費（0〜3,500）
    let medical: [Int] = [2000, 0, 3000, 1000, 3000, 0, 2500, 0, 3500, 0, 3000, 0]
    // 通信・サブスク（毎月 7,500）
    let commsMonthly = 7500
    // 家賃（毎月 100,000）
    let rentMonthly = 100000
    
    // 月ごとの合計チェックのため、必要な調整だけ先に行う（範囲逸脱の月は daily を微調整）
    // 3月: 合計 200,000 に合わせる（daily 6,500）
    daily[2] = 6500
    // 5月: 合計 200,000 に合わせる（daily 9,500）
    daily[4] = 9500
    // 7月: 合計 199,000 に合わせる（other を使わず daily 10,500）
    daily[6] = 10500
    // 9月: 合計 200,000 に合わせる（daily 2,000）
    daily[8] = 2000
    // 11月: 合計 200,000 に合わせる（daily 8,500）
    daily[10] = 8500
    // 12月: 合計 169,700（そのまま）
    
    // ===== 取引を構築 =====
    var txs: [BackupTransaction] = []
    let cal = Calendar(identifier: .gregorian)
    func isoDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(calendar: cal, timeZone: TimeZone(secondsFromGMT: 0), year: y, month: m, day: d, hour: 15))!
    }
    
    for m in 1...12 {
        let i = m - 1
        
        // 収入（毎月 25 万円：給与）
        txs.append(.init(
            id: UUID(),
            date: isoDate(2025, m, 25),
            amount: 250_000,
            typeRaw: "income",
            memo: "給与",
            categoryId: catSalary
        ))
        
        // 支出（家賃・サブスク・食費・医療・光熱・交通・娯楽・日用品）
        txs.append(.init(id: UUID(), date: isoDate(2025, m, 1),  amount: rentMonthly,    typeRaw: "expense", memo: "家賃",            categoryId: catRent))
        txs.append(.init(id: UUID(), date: isoDate(2025, m, 5),  amount: commsMonthly,   typeRaw: "expense", memo: "モバイル/ネット",  categoryId: catComms))
        txs.append(.init(id: UUID(), date: isoDate(2025, m, 10), amount: food[i],        typeRaw: "expense", memo: "食費",            categoryId: catFood))
        if medical[i] > 0 {
            txs.append(.init(id: UUID(), date: isoDate(2025, m, 12), amount: medical[i], typeRaw: "expense", memo: "医療費",          categoryId: catMedical))
        }
        txs.append(.init(id: UUID(), date: isoDate(2025, m, 15), amount: utility[i],     typeRaw: "expense", memo: "光熱費",          categoryId: catUtility))
        txs.append(.init(id: UUID(), date: isoDate(2025, m, 18), amount: transport[i],   typeRaw: "expense", memo: "交通費",          categoryId: catTransport))
        txs.append(.init(id: UUID(), date: isoDate(2025, m, 20), amount: leisure[i],     typeRaw: "expense", memo: "娯楽",            categoryId: catLeisure))
        txs.append(.init(id: UUID(), date: isoDate(2025, m, 22), amount: daily[i],       typeRaw: "expense", memo: "日用品",          categoryId: catDaily))
    }
    
    // ===== テーマ（適当な固定値） =====
    let theme = BackupTheme(
        activePresetRaw: "custom",
        useSameAccentForBoth: true,
        accentLightHex: "#FF7D19FF",
        accentDarkHex:  "#FF7D19FF",
        useSameBackgroundForBoth: false,
        backgroundLightHex: "#FAFAFAFF",
        backgroundDarkHex:  "#121212FF"
    )
    
    // ===== 毎月 ToDo（任意。家賃 1日の例を 27日にしても OK）=====
    let recurring: [BackupRecurringTodo] = [
        .init(id: UUID(), title: "家賃の支払い", dayOfMonth: 1, isActive: true)
    ]

    let dayNotes: [BackupDayNote] = [
        .init(dateKey: "2025-01-01", text: "お正月の帰省"),
        .init(dateKey: "2025-01-15", text: "クレジット締め日")
    ]

    let monthStart = BackupMonthStartSettings(
        isCustomStartEnabled: true,
        boundaryTypeRaw: "endDay",
        startDay: 25,
        holidayAdjustmentRaw: "previousWeekday"
    )

    // ===== 完全バックアップを構築 =====
    let backup = KaKeBoBackupV1(
        exportedAt: Date(),
        categories: categories,
        transactions: txs,
        recurringTodos: recurring,
        dayNotes: dayNotes,
        monthStartSettings: monthStart,
        theme: theme
    )
    
    let enc = JSONEncoder()
    enc.dateEncodingStrategy = .iso8601
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? enc.encode(backup)) ?? Data()
}
