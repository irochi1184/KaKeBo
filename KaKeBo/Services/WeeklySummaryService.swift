//
//  WeeklySummaryService.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2026/05/18.
//

import Foundation

struct WeeklySummaryService {

    struct Summary {
        /// 曜日別支出（月=0 〜 日=6）、今週分
        let dailyExpenses: [Int]
        /// 今週の支出合計（月〜今日）
        let thisWeekTotal: Int
        /// 先週の同じ曜日時点までの支出合計
        let lastWeekSamePointTotal: Int
        /// 先週の支出合計（月〜日、全7日分）
        let lastWeekTotal: Int
        /// 今日の曜日インデックス（月=0 〜 日=6）
        let todayIndex: Int

        /// 先週同時点比（%）。先週0の場合は nil
        var comparisonPercent: Double? {
            guard lastWeekSamePointTotal > 0 else { return nil }
            return Double(thisWeekTotal - lastWeekSamePointTotal) / Double(lastWeekSamePointTotal) * 100
        }

        /// ひとことコメント
        var comment: String {
            guard let pct = comparisonPercent else {
                if thisWeekTotal == 0 { return "今週はまだ支出がありません" }
                return "先週のデータがないため比較できません"
            }
            if pct <= -20 { return "先週よりかなり抑えられています" }
            if pct < -5 { return "先週より少し抑えられています" }
            if pct <= 5 { return "先週とほぼ同じペースです" }
            if pct <= 20 { return "先週より少し多めのペースです" }
            return "先週よりかなり多めのペースです"
        }
    }

    /// 取引データから今週・先週のサマリーを計算
    static func calculate(transactions: [Transaction], now: Date = Date()) -> Summary {
        let cal = Calendar(identifier: .gregorian)

        // 今日の曜日（月=0 〜 日=6）
        let weekday = cal.component(.weekday, from: now)
        // Calendar.weekday: 日=1, 月=2, ..., 土=7 → 月=0 基準に変換
        let todayIndex = (weekday + 5) % 7

        // 今週の月曜日 00:00
        let thisMonday = mondayOfWeek(containing: now, calendar: cal)
        // 先週の月曜日
        let lastMonday = cal.date(byAdding: .day, value: -7, to: thisMonday)!

        // 今日の終わり
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        // 先週の同じ曜日の終わり
        let lastWeekSameDay = cal.date(byAdding: .day, value: -7, to: endOfToday)!
        // 先週の日曜の終わり
        let lastSunday = cal.date(byAdding: .day, value: -1, to: thisMonday)!
        let endOfLastSunday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: lastSunday)!

        let expenses = transactions.filter { $0.type == .expense }

        // 今週の曜日別支出
        var dailyExpenses = [Int](repeating: 0, count: 7)
        for tx in expenses {
            if tx.date >= thisMonday && tx.date <= endOfToday {
                let dayOffset = cal.dateComponents([.day], from: thisMonday, to: tx.date).day ?? 0
                if dayOffset >= 0 && dayOffset < 7 {
                    dailyExpenses[dayOffset] += tx.amount
                }
            }
        }

        let thisWeekTotal = dailyExpenses.prefix(todayIndex + 1).reduce(0, +)

        // 先週の同時点までの合計
        let lastWeekSamePointTotal = expenses.filter {
            $0.date >= lastMonday && $0.date <= lastWeekSameDay
        }.reduce(0) { $0 + $1.amount }

        // 先週全体の合計
        let lastWeekTotal = expenses.filter {
            $0.date >= lastMonday && $0.date <= endOfLastSunday
        }.reduce(0) { $0 + $1.amount }

        return Summary(
            dailyExpenses: dailyExpenses,
            thisWeekTotal: thisWeekTotal,
            lastWeekSamePointTotal: lastWeekSamePointTotal,
            lastWeekTotal: lastWeekTotal,
            todayIndex: todayIndex
        )
    }

    // その週の月曜日 00:00 を返す
    private static func mondayOfWeek(containing date: Date, calendar: Calendar) -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // 月曜始まり
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: components) ?? date
    }
}
