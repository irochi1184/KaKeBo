//
//  Views/Calendar/CalendarMonthGrid.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/23.
//

import SwiftUI

struct CalendarMonthGrid: View {
    let month: Date
    /// その月の各日の支出合計（正）
    let expenseBuckets: [Date: Int]
    /// その月の各日の収入合計（正）
    let incomeBuckets:  [Date: Int]
    let maxExpense: Int
    let maxIncome:  Int
    let todoCounts: [Date: Int]
    let accent: Color
    let selectedDate: Date?
    let onTapDay: (Date) -> Void
    let onLongPressDay: (Date) -> Void
    let notedDays: Set<Date>
    let noteSnippets: [Date: String]
    
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    private var cal: Calendar { Calendar.current }
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            let days = daysInMonth()
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day = day {
                    let key = cal.startOfDay(for: day)
                    let k = cal.startOfDay(for: day)
                    DayCell(
                        date: day,
                        expense: expenseBuckets[key] ?? 0,
                        income: incomeBuckets[key] ?? 0,
                        maxExpense: maxExpense,
                        maxIncome: maxIncome,
                        isToday: cal.isDateInToday(day),
                        isSelected: selectedDate.map { cal.isDate(day, inSameDayAs: $0) } ?? false,
                        todoCount: todoCounts[k] ?? 0,
                        accent: accent,
                        hasNote: notedDays.contains(key),
                        noteSnippet: noteSnippets[key]
                    )
                    .onTapGesture { onTapDay(day) }
                    .onLongPressGesture(minimumDuration: 0.3) { onLongPressDay(day) }
                } else {
                    Color.clear.frame(height: 54)
                }
            }
        }
    }
    
    /// 6行×7列で該当月を並べる（先頭の空白は nil）
    private func daysInMonth() -> [Date?] {
        var result: [Date?] = []
        
        let comps = cal.dateComponents([.year,.month], from: month)
        guard let firstDay = cal.date(from: comps) else { return [] }
        
        guard let range = cal.range(of: .day, in: .month, for: firstDay) else {
            return []
        }
        let firstWeekday = cal.component(.weekday, from: firstDay) // 1:日〜7:土
        let leadingBlanks = (firstWeekday - cal.firstWeekday + 7) % 7
        
        result.append(contentsOf: Array(repeating: nil, count: leadingBlanks))
        
        for day in range {
            if let d = cal.date(from: DateComponents(year: comps.year, month: comps.month, day: day)) {
                result.append(d)
            }
        }
        
        // 42マスにパディング
        while result.count % 7 != 0 { result.append(nil) }
        if result.count < 42 { result.append(contentsOf: Array(repeating: nil, count: 42 - result.count)) }
        
        return result
    }
}

private struct DayCell: View {
    let date: Date
    let expense: Int
    let income: Int
    let maxExpense: Int
    let maxIncome: Int
    let isToday: Bool
    let isSelected: Bool
    let todoCount: Int
    let accent: Color
    let hasNote: Bool
    let noteSnippet: String?
    
    private var cal: Calendar { Calendar.current }
    
    var body: some View {
        ZStack(alignment: .topLeading) {   // ← 右上から左上に変更
            // 枠
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isToday ? accent.opacity(0.6) : accent.opacity(0.4),
                        lineWidth: isToday ? 1.6 : 0.8)

            if isSelected {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(accent.opacity(0.1))
            }
            
            VStack(spacing: 4) {
                // 上：日付は右上に表示
                HStack {
                    Spacer(minLength: 0)
                    Text("\(cal.component(.day, from: date))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                        .padding(.trailing, 6)
                }
                
                // 下：支出・収入
                VStack(alignment: .trailing, spacing: 3) {
                    if income > 0 {
                        AmountLabel(
                            text: "¥" + decimal(income),
                            isIncome: true,
                            strength: intensity(value: income, max: maxIncome)
                        )
                    }
                    if expense > 0 {
                        AmountLabel(
                            text: "¥" + decimal(expense),
                            isIncome: false,
                            strength: intensity(value: expense, max: maxExpense)
                        )
                    }
                }
                .padding(.horizontal, 3)
                .padding(.bottom, 3)
            }
            
            // ▼ ToDoバッジ（左上）
            if todoCount > 0 {
                Text(todoCount > 9 ? "9+" : "\(todoCount)")
                    .font(.system(size: 8, weight: .semibold))   // ← フォントを少し小さめ
                    .monospacedDigit()
                    .padding(.vertical, 1.8)   // ← 縦パディングを微調整
                    .padding(.horizontal, 4.5) // ← 横パディングを微調整
                    .background(Capsule().fill(accent.opacity(0.9)))
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
                    .padding(.top, 4)
                    .accessibilityLabel("ToDo \(todoCount) 件")
            }
            // ▼ メモスニペット（左下、1行・超小さく）
            if let s = noteSnippet, !s.isEmpty {
                Text(s)
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 3)
                    .padding(.bottom, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(maxHeight: .infinity, alignment: .bottomLeading)
                } else if hasNote {
                    // スニペットがない時だけ控えめなピン
                    Image(systemName: "note.text")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.95))
                        .padding(.leading, 4)
                        .padding(.bottom, 4)
                        .frame(maxHeight: .infinity, alignment: .bottomLeading)
                }
        }
        .frame(height: 56) // 少し縦に余裕（必要なら 56〜60 に調整）
    }
    
    // 等幅＆縮小で見切れない十進数表記
    private func decimal(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: n as NSNumber) ?? "\(n)"
    }
    
    // 金額に応じて濃さ変化
    private func color(for amount: Int, max: Int, base: Color) -> Color {
        guard max > 0 else { return base.opacity(0.35) }
        let ratio = min(Double(amount) / Double(max), 1.0)
        return base.opacity(0.25 + 0.55 * ratio)
    }
}

// 数値だけを右揃えで出すラベル
private struct AmountLabel: View {
    @Environment(\.colorScheme) private var scheme
    let text: String          // 例: "¥12,345"
    let isIncome: Bool        // true=緑, false=赤
    let strength: Double      // 0...1 : 大きいほど濃い
    
    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(dynamicColor)
            .frame(maxWidth: .infinity, alignment: .trailing)  // 右揃え
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .allowsTightening(true)
            .padding(.trailing, 2)
    }
    
    private var dynamicColor: Color {
        let base = isIncome ? Color.green : Color.red
        // ダークモードではやや淡く、かつ強さで少し濃淡をつける
        let darkFactor = (scheme == .dark) ? 0.85 : 1.0
        let strengthFactor = 0.6 + 0.4 * max(0.0, min(1.0, strength))  // 0.6〜1.0
        return base.opacity(darkFactor * strengthFactor)
    }
}

// 値に応じた“強さ”(0...1) を作る簡単な関数
private func intensity(value: Int, max: Int) -> Double {
    guard max > 0 else { return 1.0 }
    let ratio = Double(value) / Double(max)
    return Swift.max(0.2, Swift.min(1.0, ratio))
}
