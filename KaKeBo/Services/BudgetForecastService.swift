import Foundation

/// 支出予測サービス：過去の支出データから今月の着地予測を算出する
struct BudgetForecastService {

    /// 予測結果
    struct Forecast {
        let projectedExpense: Int       // 今月の着地予測額
        let averageMonthlyExpense: Int  // 過去3ヶ月の月平均支出
        let currentExpense: Int         // 今月のここまでの支出
        let daysElapsed: Int            // 今月の経過日数
        let daysInMonth: Int            // 今月の総日数
        let budgetLimit: Int?           // 設定された予算上限（nil = 未設定）
        let isOverBudget: Bool          // 予測が予算超過かどうか
        let overBudgetAmount: Int       // 超過予測額（0以下なら超過なし）
        let progressRatio: Double       // 予算消化率（0.0〜1.0+）
        let categoryForecasts: [CategoryForecast] // カテゴリ別予測
    }

    /// カテゴリ別の予測
    struct CategoryForecast: Identifiable {
        let id: UUID
        let categoryName: String
        let currentExpense: Int
        let projectedExpense: Int
        let averageExpense: Int
        let budgetLimit: Int?
        let isOverBudget: Bool
    }

    /// 予測を計算する
    /// - Parameters:
    ///   - transactions: 全取引データ
    ///   - budgets: 予算設定
    ///   - categories: カテゴリ一覧
    ///   - currentMonth: 対象月の先頭日
    ///   - resolver: 月開始日の解決
    static func calculate(
        transactions: [Transaction],
        budgets rawBudgets: [Budget],
        categories: [Category],
        currentMonth: Date,
        resolver: MonthStartResolver
    ) -> Forecast {
        // 無効化（一時停止）された予算は未設定扱いにする
        let budgets = rawBudgets.filter { $0.isEnabled }
        let cal = Calendar.current
        let today = Date()

        // 今月の範囲
        let monthRange = resolver.monthRange(for: currentMonth)
        let daysInMonth = cal.dateComponents([.day], from: monthRange.lowerBound, to: monthRange.upperBound).day ?? 30
        let daysElapsed = max(1, cal.dateComponents([.day], from: monthRange.lowerBound, to: min(today, monthRange.upperBound)).day ?? 1)

        // 今月の支出
        let currentMonthTx = transactions.filter { tx in
            tx.type == .expense && tx.date >= monthRange.lowerBound && tx.date < monthRange.upperBound
        }
        let currentExpense = currentMonthTx.reduce(0) { $0 + $1.amount }

        // 過去3ヶ月の支出平均
        let pastMonthsExpenses = (1...3).map { offset -> Int in
            guard let pastMonth = cal.date(byAdding: .month, value: -offset, to: currentMonth) else { return 0 }
            let range = resolver.monthRange(for: pastMonth)
            return transactions
                .filter { $0.type == .expense && $0.date >= range.lowerBound && $0.date < range.upperBound }
                .reduce(0) { $0 + $1.amount }
        }
        let nonZeroMonths = pastMonthsExpenses.filter { $0 > 0 }
        let averageMonthlyExpense = nonZeroMonths.isEmpty ? 0 : nonZeroMonths.reduce(0, +) / nonZeroMonths.count

        // 着地予測：今月の日割り支出ペースから月末を推定
        let dailyRate = Double(currentExpense) / Double(daysElapsed)
        let projectedExpense: Int
        if today >= monthRange.upperBound {
            // 月末を過ぎている場合は実績値をそのまま使用
            projectedExpense = currentExpense
        } else {
            projectedExpense = Int(dailyRate * Double(daysInMonth))
        }

        // 予算上限（月別 or カテゴリ全体合計）
        let monthId = monthIdString(for: currentMonth)
        let totalBudgetLimit: Int? = {
            let monthBudgets = budgets.filter { $0.monthId == monthId }
            if monthBudgets.isEmpty { return nil }
            return monthBudgets.reduce(0) { $0 + $1.limitAmount }
        }()

        let isOverBudget: Bool
        let overBudgetAmount: Int
        let progressRatio: Double

        if let limit = totalBudgetLimit, limit > 0 {
            isOverBudget = projectedExpense > limit
            overBudgetAmount = projectedExpense - limit
            progressRatio = Double(currentExpense) / Double(limit)
        } else if averageMonthlyExpense > 0 {
            // 予算未設定の場合は過去平均を基準にする
            isOverBudget = projectedExpense > averageMonthlyExpense
            overBudgetAmount = projectedExpense - averageMonthlyExpense
            progressRatio = Double(currentExpense) / Double(averageMonthlyExpense)
        } else {
            isOverBudget = false
            overBudgetAmount = 0
            progressRatio = 0
        }

        // カテゴリ別予測
        let categoryForecasts = buildCategoryForecasts(
            currentMonthTx: currentMonthTx,
            transactions: transactions,
            budgets: budgets.filter { $0.monthId == monthId },
            categories: categories,
            currentMonth: currentMonth,
            daysElapsed: daysElapsed,
            daysInMonth: daysInMonth,
            resolver: resolver,
            cal: cal
        )

        return Forecast(
            projectedExpense: projectedExpense,
            averageMonthlyExpense: averageMonthlyExpense,
            currentExpense: currentExpense,
            daysElapsed: daysElapsed,
            daysInMonth: daysInMonth,
            budgetLimit: totalBudgetLimit,
            isOverBudget: isOverBudget,
            overBudgetAmount: overBudgetAmount,
            progressRatio: progressRatio,
            categoryForecasts: categoryForecasts
        )
    }

    private static func buildCategoryForecasts(
        currentMonthTx: [Transaction],
        transactions: [Transaction],
        budgets: [Budget],
        categories: [Category],
        currentMonth: Date,
        daysElapsed: Int,
        daysInMonth: Int,
        resolver: MonthStartResolver,
        cal: Calendar
    ) -> [CategoryForecast] {
        // 今月のカテゴリ別支出
        var currentByCategory: [UUID: Int] = [:]
        for tx in currentMonthTx {
            currentByCategory[tx.categoryId, default: 0] += tx.amount
        }

        // 過去3ヶ月のカテゴリ別平均
        var avgByCategory: [UUID: Int] = [:]
        for cat in categories {
            let pastAmounts = (1...3).compactMap { offset -> Int? in
                guard let pastMonth = cal.date(byAdding: .month, value: -offset, to: currentMonth) else { return nil }
                let range = resolver.monthRange(for: pastMonth)
                let amount = transactions
                    .filter { $0.type == .expense && $0.categoryId == cat.id && $0.date >= range.lowerBound && $0.date < range.upperBound }
                    .reduce(0) { $0 + $1.amount }
                return amount > 0 ? amount : nil
            }
            if !pastAmounts.isEmpty {
                avgByCategory[cat.id] = pastAmounts.reduce(0, +) / pastAmounts.count
            }
        }

        // 予測を構築（支出があるカテゴリのみ）
        let relevantCategoryIds = Set(currentByCategory.keys).union(Set(avgByCategory.keys))

        return categories
            .filter { relevantCategoryIds.contains($0.id) }
            .map { cat in
                let current = currentByCategory[cat.id] ?? 0
                let avg = avgByCategory[cat.id] ?? 0
                let dailyRate = Double(current) / Double(daysElapsed)
                let projected = Int(dailyRate * Double(daysInMonth))
                let budget = budgets.first(where: { $0.categoryId == cat.id })
                let limit = budget?.limitAmount
                let isOver: Bool = {
                    if let l = limit { return projected > l }
                    return avg > 0 && projected > avg
                }()

                return CategoryForecast(
                    id: cat.id,
                    categoryName: cat.name,
                    currentExpense: current,
                    projectedExpense: projected,
                    averageExpense: avg,
                    budgetLimit: limit,
                    isOverBudget: isOver
                )
            }
            .sorted { $0.projectedExpense > $1.projectedExpense }
    }

    private static func monthIdString(for date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
}
