//
//  Views/Calendar/CalendarScreen.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/23.
//

import SwiftUI

struct CalendarScreen: View {
    @EnvironmentObject var store: DataStore
    private var cal: Calendar { .current }
    
    // 年月
    @State private var month: Date = Calendar.current.date(from:Calendar.current.dateComponents([.year,.month], from: .now)
    ) ?? .now
    
    // どのシートを出すか（単一ソース・オブ・トゥルース）
    @State private var sheet: Sheet?
    
    enum Sheet: Identifiable, Equatable {
        case detail(Date)
        case add(Date)
        var id: String {
            switch self {
            case .detail(let d): return "detail-\(d.timeIntervalSince1970)"
            case .add(let d):    return "add-\(d.timeIntervalSince1970)"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                
                // 年月ヘッダー
                HStack(spacing: 12) {
                    Button { month = cal.date(byAdding: .month, value: -1, to: month) ?? month } label: {
                        Image(systemName: "chevron.left.circle.fill").font(.title3).symbolRenderingMode(.hierarchical)
                    }
                    Spacer()
                    Text(title(month))
                        .font(.headline.weight(.semibold))
                        .padding(.vertical, 4).padding(.horizontal, 10)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.thinMaterial))
                    Spacer()
                    Button { month = cal.date(byAdding: .month, value: 1, to: month) ?? month } label: {
                        Image(systemName: "chevron.right.circle.fill").font(.title3).symbolRenderingMode(.hierarchical)
                    }
                }
                .padding(.horizontal)
                
                // 曜日ヘッダー
                HStack {
                    ForEach(weekdaySymbolsJP, id: \.self) { w in
                        Text(w).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 8)
                
                // 月グリッド
                CalendarMonthGrid(
                    month: month,
                    expenseBuckets: expenseBuckets,
                    incomeBuckets: incomeBuckets,
                    maxExpense: maxExpenseInMonth,
                    maxIncome: maxIncomeInMonth,
                    onTapDay: { day in
                        sheet = .detail(day)      // ← 1タップは必ず詳細
                    },
                    onLongPressDay: { day in
                        sheet = .add(day)         // ← 長押しは追加
                    }
                )
                .padding(.horizontal)
                
                Spacer(minLength: 8)
            }
            .navigationTitle("カレンダー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        sheet = .add(.now)        // 右上＋は今日で追加
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(item: $sheet) { s in
                switch s {
                case .detail(let date):
                    DayDetailSheet(date: date)
                        .environmentObject(store)
                case .add(_):
                    // AddTransactionView に初期日付を渡したい場合は
                    // init を増やすか、DataStore 経由で適用してください
                    AddTransactionView(defaultCategoryId: store.categories.first?.id)
                        .environmentObject(store)
                }
            }
        }
    }
    
    // MARK: - 集計
    private var transactionsThisMonth: [Transaction] {
        store.transactions.filter { cal.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    
    /// 日別 “支出” 合計
    private var expenseBuckets: [Date: Int] {
        var dict: [Date: Int] = [:]
        for tx in transactionsThisMonth where tx.type == .expense {
            let key = cal.startOfDay(for: tx.date)
            dict[key, default: 0] += tx.amount
        }
        return dict
    }
    
    /// 日別 “収入” 合計
    private var incomeBuckets: [Date: Int] {
        var dict: [Date: Int] = [:]
        for tx in transactionsThisMonth where tx.type == .income {
            let key = cal.startOfDay(for: tx.date)
            dict[key, default: 0] += tx.amount
        }
        return dict
    }
    
    /// 今月の最大支出・最大収入（セルの濃淡に使用）
    private var maxExpenseInMonth: Int { expenseBuckets.values.max() ?? 0 }
    private var maxIncomeInMonth:  Int { incomeBuckets.values.max() ?? 0 }
    
    private func title(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return f.string(from: date)
    }
    
    private var weekdaySymbolsJP: [String] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        return f.shortStandaloneWeekdaySymbols
    }
}
