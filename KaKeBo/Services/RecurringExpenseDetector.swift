import Foundation

/// 繰り返し支出を自動検出するサービス
/// 過去の取引���ら毎月繰り返されるパターンを検出し、固定費テンプレートへの登録を提案する
struct RecurringExpenseDetector {

    /// 検出された繰り返し支出パターン
    struct DetectedPattern: Identifiable, Hashable {
        let id = UUID()
        let categoryId: UUID
        let categoryName: String
        let averageAmount: Int
        let medianDay: Int          // 支払い��の中央値
        let memo: String            // 最頻���メモ
        let monthsDetected: Int     // 検出された月数
        let confidence: Double      // 信頼度 (0.0〜1.0)
        let recentAmounts: [Int]    // 直近の金額推移
    }

    /// 検出パラメータ
    struct Config {
        /// 繰り返しとみなす最小月数
        var minMonths: Int = 3
        /// 金���の変動許容率（中央値からの乖離率）
        var amountToleranceRatio: Double = 0.25
        /// 分析対象の最大月数
        var lookbackMonths: Int = 6
    }

    /// 繰り返し支出パタ���ンを検出する
    static func detect(
        transactions: [Transaction],
        categories: [Category],
        existingTemplates: [FixedExpenseTemplate],
        resolver: MonthStartResolver,
        config: Config = Config()
    ) -> [DetectedPattern] {
        let cal = Calendar.current
        let today = Date()
        guard let startDate = cal.date(byAdding: .month, value: -config.lookbackMonths, to: today) else {
            return []
        }

        // 対象期間の支出のみ
        let expenses = transactions.filter { tx in
            tx.type == .expense && tx.date >= startDate && tx.date <= today
        }

        // カテゴリ×メモ類似グループで集計
        let grouped = groupByPattern(expenses: expenses, cal: cal)

        // 既に登録済みの固定費テンプレートのカテゴリ+金額を除外するためのセット
        let existingKeys = Set(existingTemplates.map { PatternKey(categoryId: $0.categoryId, amount: $0.amount) })

        var results: [DetectedPattern] = []

        for (key, monthlyEntries) in grouped {
            // 登録済みのパター��に近いものはスキップ
            let avgAmount = monthlyEntries.flatMap(\.amounts).reduce(0, +) / max(1, monthlyEntries.flatMap(\.amounts).count)
            if existingKeys.contains(where: { $0.categoryId == key.categoryId && isAmountSimilar($0.amount, avgAmount) }) {
                continue
            }

            // 出現月数チェック
            let uniqueMonths = Set(monthlyEntries.map { $0.monthKey })
            guard uniqueMonths.count >= config.minMonths else { continue }

            // 金額の一貫性チェック
            let allAmounts = monthlyEntries.flatMap(\.amounts)
            let median = medianValue(allAmounts)
            let consistent = allAmounts.filter { abs(Double($0 - median) / Double(max(1, median))) <= config.amountToleranceRatio }
            let consistencyRatio = Double(consistent.count) / Double(allAmounts.count)
            guard consistencyRatio >= 0.6 else { continue }

            // 信頼度計算
            let monthCoverage = Double(uniqueMonths.count) / Double(config.lookbackMonths)
            let confidence = min(1.0, (monthCoverage * 0.5 + consistencyRatio * 0.5))

            // 支払い日の中央値
            let days = monthlyEntries.flatMap(\.days)
            let medianDay = medianValue(days)

            // 最頻出メモ
            let topMemo = mostFrequentMemo(monthlyEntries.flatMap(\.memos))

            // カテゴリ名
            let categoryName = categories.first(where: { $0.id == key.categoryId })?.name ?? "不明"

            // 直近の金額
            let sortedEntries = monthlyEntries.sorted { $0.monthKey < $1.monthKey }
            let recentAmounts = Array(sortedEntries.suffix(4).map { $0.amounts.reduce(0, +) })

            results.append(DetectedPattern(
                categoryId: key.categoryId,
                categoryName: categoryName,
                averageAmount: avgAmount,
                medianDay: medianDay,
                memo: topMemo,
                monthsDetected: uniqueMonths.count,
                confidence: confidence,
                recentAmounts: recentAmounts
            ))
        }

        return results.sorted { $0.confidence > $1.confidence }
    }

    // MARK: - Private

    private struct PatternKey: Hashable {
        let categoryId: UUID
        let amount: Int // 概算金額（1000円単位に丸め）
    }

    private struct GroupKey: Hashable {
        let categoryId: UUID
        let memoPrefix: String // メモの先頭10文字で類似グループ化
    }

    private struct MonthEntry {
        let monthKey: String    // "yyyy-MM"
        let amounts: [Int]
        let days: [Int]
        let memos: [String]
    }

    /// カテゴリ×メモ類似でグループ化し、月別に集約する
    private static func groupByPattern(expenses: [Transaction], cal: Calendar) -> [GroupKey: [MonthEntry]] {
        // まずカテゴリ×メモプレフィックスでグループ化
        var grouped: [GroupKey: [(monthKey: String, amount: Int, day: Int, memo: String)]] = [:]

        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale(identifier: "ja_JP")
        monthFormatter.dateFormat = "yyyy-MM"

        for tx in expenses {
            let memoPrefix = String(tx.memo.prefix(10)).trimmingCharacters(in: .whitespaces)
            let key = GroupKey(categoryId: tx.categoryId, memoPrefix: memoPrefix)
            let monthKey = monthFormatter.string(from: tx.date)
            let day = cal.component(.day, from: tx.date)
            grouped[key, default: []].append((monthKey: monthKey, amount: tx.amount, day: day, memo: tx.memo))
        }

        // 月別に集約
        var result: [GroupKey: [MonthEntry]] = [:]
        for (key, entries) in grouped {
            let byMonth = Dictionary(grouping: entries, by: \.monthKey)
            let monthEntries = byMonth.map { (monthKey, items) in
                MonthEntry(
                    monthKey: monthKey,
                    amounts: items.map(\.amount),
                    days: items.map(\.day),
                    memos: items.map(\.memo)
                )
            }
            // 1月に複��回同額の支出がある場合は除外（日用品等の可能性）
            let avgPerMonth = Double(entries.count) / Double(Set(entries.map(\.monthKey)).count)
            if avgPerMonth <= 2.0 {
                result[key] = monthEntries
            }
        }

        return result
    }

    private static func medianValue(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func mostFrequentMemo(_ memos: [String]) -> String {
        let cleaned = memos.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return "" }
        var counts: [String: Int] = [:]
        for m in cleaned { counts[m, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? ""
    }

    private static func isAmountSimilar(_ a: Int, _ b: Int) -> Bool {
        guard a > 0 && b > 0 else { return false }
        let ratio = abs(Double(a - b)) / Double(max(a, b))
        return ratio < 0.15
    }
}
