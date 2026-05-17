import SwiftUI

/// ホーム画面に表示する支出予測カード
struct BudgetForecastCard: View {
    let forecast: BudgetForecastService.Forecast
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.appExpenseColor) private var expenseColor
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // タイトル行
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(themeStore.theme.accentColor(for: scheme))
                Text("支出予測")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(forecast.daysElapsed)/\(forecast.daysInMonth)日経過")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // 予測メイン
            VStack(spacing: 8) {
                // プログレスバー
                budgetProgressBar

                // 予測金額
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("着地予測")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currency(forecast.projectedExpense))
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(forecast.isOverBudget ? .red : .primary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(referenceLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(currency(referenceAmount))
                            .font(.callout.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                // 超過警告
                if forecast.isOverBudget && forecast.overBudgetAmount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Text("\(currency(forecast.overBudgetAmount)) 超過見込み")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.1))
                    )
                }
            }

            // カテゴリ別（上位3件のみ）
            if !forecast.categoryForecasts.isEmpty {
                Divider()
                categorySection
            }
        }
        .padding(16)
    }

    // MARK: - プログレスバー
    @ViewBuilder
    private var budgetProgressBar: some View {
        let ratio = min(forecast.progressRatio, 1.5)
        let barColor: Color = {
            if forecast.progressRatio > 1.0 { return .red }
            if forecast.progressRatio > 0.8 { return .orange }
            return expenseColor
        }()

        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 背景
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                        .frame(height: 8)

                    // 実績バー
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(barColor.gradient)
                        .frame(width: geo.size.width * min(ratio, 1.0), height: 8)

                    // 100%ライン（予算設定時のみ）
                    if forecast.budgetLimit != nil || forecast.averageMonthlyExpense > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.4))
                            .frame(width: 1.5, height: 12)
                            .offset(x: geo.size.width * min(1.0, 1.0) - 0.75)
                    }
                }
            }
            .frame(height: 12)

            // ラベル
            HStack {
                Text("現在: \(currency(forecast.currentExpense))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if forecast.progressRatio > 0 {
                    Text("\(Int(forecast.progressRatio * 100))%")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(forecast.progressRatio > 1.0 ? .red : .secondary)
                }
            }
        }
    }

    // MARK: - カテゴリセクション
    @ViewBuilder
    private var categorySection: some View {
        let topCategories = Array(forecast.categoryForecasts.prefix(3))
        VStack(alignment: .leading, spacing: 6) {
            Text("カテゴリ別予測（上位）")
                .font(.caption)
                .foregroundStyle(.tertiary)

            ForEach(topCategories) { cat in
                HStack {
                    Circle()
                        .fill(cat.isOverBudget ? Color.red.opacity(0.7) : Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                    Text(cat.categoryName)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Text(currency(cat.projectedExpense))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(cat.isOverBudget ? .red : .primary)
                }
            }
        }
    }

    // MARK: - ヘルパー
    private var referenceLabel: String {
        forecast.budgetLimit != nil ? "予算" : "過去3ヶ月平均"
    }

    private var referenceAmount: Int {
        forecast.budgetLimit ?? forecast.averageMonthlyExpense
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}
