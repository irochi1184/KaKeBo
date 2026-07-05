//
//  Utilities/MonthStartResolver.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/12/08.
//

import Foundation

protocol HolidayChecking {
    func isHoliday(_ date: Date) -> Bool
}

/// 日本の祝日と週末を判定する簡易プロバイダ
final class JapaneseHolidayProvider: HolidayChecking {
    private let calendar: Calendar
    private var cache: [Int: Set<Date>] = [:]

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        var cal = calendar
        cal.locale = Locale(identifier: "ja_JP")
        self.calendar = cal
    }

    func isHoliday(_ date: Date) -> Bool {
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: day)
        if let cached = cache[year] { return cached.contains(day) }

        let generated = generateHolidays(for: year)
        cache[year] = generated
        return generated.contains(day)
    }

    private func generateHolidays(for year: Int) -> Set<Date> {
        var holidays: Set<Date> = []

        func makeDate(month: Int, day: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day)).map { calendar.startOfDay(for: $0) }
        }

        func appendIfValid(_ date: Date?) {
            if let d = date { holidays.insert(d) }
        }

        // 固定日
        [
            (1, 1),   // 元日
            (2, 11),  // 建国記念の日
            (2, 23),  // 天皇誕生日
            (4, 29),  // 昭和の日
            (5, 3),   // 憲法記念日
            (5, 4),   // みどりの日
            (5, 5),   // こどもの日
            (8, 11),  // 山の日
            (11, 3),  // 文化の日
            (11, 23)  // 勤労感謝の日
        ].forEach { month, day in appendIfValid(makeDate(month: month, day: day)) }

        // ハッピーマンデー制
        appendIfValid(nthWeekday(occurrence: 2, weekday: 2, month: 1, year: year))   // 成人の日（1月第2月曜）
        appendIfValid(nthWeekday(occurrence: 3, weekday: 2, month: 7, year: year))   // 海の日（7月第3月曜）
        appendIfValid(nthWeekday(occurrence: 3, weekday: 2, month: 9, year: year))   // 敬老の日（9月第3月曜）
        appendIfValid(nthWeekday(occurrence: 2, weekday: 2, month: 10, year: year))  // スポーツの日（10月第2月曜）

        // 春分・秋分（簡易計算式：2000-2050頃まで有効）
        if let vernal = vernalEquinox(year: year) { appendIfValid(makeDate(month: 3, day: vernal)) }
        if let autumnal = autumnalEquinox(year: year) { appendIfValid(makeDate(month: 9, day: autumnal)) }

        // 国民の休日（祝日に挟まれた平日）
        addCitizenHolidays(to: &holidays)
        // 振替休日（日曜に当たる祝日の補填）
        addSubstituteHolidays(to: &holidays)

        return holidays
    }

    private func nthWeekday(occurrence: Int, weekday: Int, month: Int, year: Int) -> Date? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.weekday = weekday
        comps.weekdayOrdinal = occurrence
        return calendar.date(from: comps).map { calendar.startOfDay(for: $0) }
    }

    private func vernalEquinox(year: Int) -> Int? {
        guard (1900...2099).contains(year) else { return nil }
        let day = floor(20.69115 + 0.2421904 * Double(year - 2000)) - floor(Double(year - 2000) / 4.0)
        return Int(day)
    }

    private func autumnalEquinox(year: Int) -> Int? {
        guard (1900...2099).contains(year) else { return nil }
        let day = floor(23.09 + 0.2421904 * Double(year - 2000)) - floor(Double(year - 2000) / 4.0)
        return Int(day)
    }

    private func addSubstituteHolidays(to holidays: inout Set<Date>) {
        let sorted = holidays.sorted()
        for day in sorted where calendar.component(.weekday, from: day) == 1 { // 日曜日
            var substitute = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            while holidays.contains(substitute) || calendar.isDateInWeekend(substitute) {
                substitute = calendar.date(byAdding: .day, value: 1, to: substitute) ?? substitute
            }
            holidays.insert(calendar.startOfDay(for: substitute))
        }
    }

    private func addCitizenHolidays(to holidays: inout Set<Date>) {
        let sorted = holidays.sorted()
        guard sorted.count >= 2 else { return }
        for idx in 1..<sorted.count {
            let prev = sorted[idx - 1]
            let curr = sorted[idx]
            if let gap = calendar.dateComponents([.day], from: prev, to: curr).day, gap == 2 {
                if let middle = calendar.date(byAdding: .day, value: 1, to: prev) {
                    if !calendar.isDateInWeekend(middle) {
                        holidays.insert(calendar.startOfDay(for: middle))
                    }
                }
            }
        }
    }
}

/// カスタム開始日に基づいて対象月の範囲を決めるヘルパ
struct MonthStartResolver {
    let settings: MonthStartSettings
    var calendar: Calendar
    let holidayProvider: HolidayChecking

    init(settings: MonthStartSettings,
         calendar: Calendar = .current,
         holidayProvider: HolidayChecking) {
        var cal = calendar
        cal.locale = Locale(identifier: "ja_JP")
        self.settings = settings
        self.calendar = cal
        self.holidayProvider = holidayProvider
    }

    func startDate(for anchorMonth: Date) -> Date {
        let baseMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: anchorMonth)) ?? anchorMonth
        guard settings.isCustomStartEnabled else { return calendar.startOfDay(for: baseMonth) }

        let offset = settings.boundaryType == .startDay ? 0 : -1
        let targetMonth = calendar.date(byAdding: .month, value: offset, to: baseMonth) ?? baseMonth
        return boundaryDate(for: targetMonth)
    }

    func monthRange(for anchorMonth: Date) -> Range<Date> {
        let start = startDate(for: anchorMonth)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: anchorMonth) ?? anchorMonth
        let nextStart = startDate(for: nextMonth)
        return start..<nextStart
    }

    func contains(_ date: Date, inMonthOf anchorMonth: Date) -> Bool {
        let interval = monthRange(for: anchorMonth)
        return date >= interval.lowerBound && date < interval.upperBound
    }

    /// 指定した日付が属する「月」を返す（開始日／締め日の設定を考慮）
    ///
    /// - Returns: 対象日付を含むアンカー月の先頭日（00:00）
    func anchorMonth(containing date: Date) -> Date {
        let base = startOfMonth(date)
        if contains(date, inMonthOf: base) { return base }

        let prev = calendar.date(byAdding: .month, value: -1, to: base).map(startOfMonth) ?? base
        if contains(date, inMonthOf: prev) { return prev }

        let next = calendar.date(byAdding: .month, value: 1, to: base).map(startOfMonth) ?? base
        if contains(date, inMonthOf: next) { return next }

        return base
    }

    private func isNonBusinessDay(_ date: Date) -> Bool {
        calendar.isDateInWeekend(date) || holidayProvider.isHoliday(date)
    }

    private func boundaryDate(for month: Date) -> Date {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month

        let days = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let clampedDay = min(max(settings.startDay, 1), days)

        guard let base = calendar.date(from: DateComponents(year: calendar.component(.year, from: monthStart),
                                                            month: calendar.component(.month, from: monthStart),
                                                            day: clampedDay)) else {
            return calendar.startOfDay(for: monthStart)
        }

        let startOfBase = calendar.startOfDay(for: base)
        guard isNonBusinessDay(startOfBase) else { return startOfBase }

        switch settings.holidayAdjustment {
        case .none:
            return startOfBase
        case .previousWeekday:
            return move(from: startOfBase, direction: -1)
        case .nextWeekday:
            return move(from: startOfBase, direction: 1)
        }
    }

    private func move(from date: Date, direction: Int) -> Date {
        var current = date
        while isNonBusinessDay(current) {
            guard let next = calendar.date(byAdding: .day, value: direction, to: current) else { break }
            current = next
        }
        return calendar.startOfDay(for: current)
    }

    private func startOfMonth(_ date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
