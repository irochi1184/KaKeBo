import SwiftUI

/// 検出された繰り返し支出の提案画面
struct RecurringExpenseSuggestionsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var monthStartStore: MonthStartStore
    @Environment(\.dismiss) private var dismiss

    @State private var patterns: [RecurringExpenseDetector.DetectedPattern] = []
    @State private var dismissed: Set<UUID> = loadDismissed()
    @State private var registeredAlert: String?

    var body: some View {
        Group {
            if visiblePatterns.isEmpty {
                emptyState
            } else {
                patternList
            }
        }
        .navigationTitle("繰り返し支出の検出")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { detectPatterns() }
        .alert("登録完了", isPresented: .init(
            get: { registeredAlert != nil },
            set: { if !$0 { registeredAlert = nil } }
        )) {
            Button("OK") { registeredAlert = nil }
        } message: {
            if let msg = registeredAlert {
                Text(msg)
            }
        }
    }

    private var visiblePatterns: [RecurringExpenseDetector.DetectedPattern] {
        patterns.filter { !dismissed.contains($0.id) }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("繰り返し支出は検出されませんでした")
                .font(.headline)
            Text("3ヶ月以上のデータが蓄積されると、毎月の定額支出を自動で提案します。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private var patternList: some View {
        List {
            Section {
                Text("以下の取引が毎月繰り返されています。固定費として登録すると自動計上されます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(visiblePatterns) { pattern in
                PatternRow(
                    pattern: pattern,
                    onRegister: { registerAsTemplate(pattern) },
                    onDismiss: { dismissPattern(pattern) }
                )
            }
        }
    }

    // MARK: - アクション

    private func detectPatterns() {
        let existingTemplates = loadExistingTemplates()
        patterns = RecurringExpenseDetector.detect(
            transactions: store.transactions,
            categories: store.categories,
            existingTemplates: existingTemplates,
            resolver: monthStartStore.resolver()
        )
    }

    private func registerAsTemplate(_ pattern: RecurringExpenseDetector.DetectedPattern) {
        let template = FixedExpenseTemplate(
            title: pattern.memo.isEmpty ? pattern.categoryName : pattern.memo,
            amount: pattern.averageAmount,
            dayOfMonth: pattern.medianDay,
            categoryId: pattern.categoryId,
            memo: pattern.memo.isEmpty ? nil : pattern.categoryName,
            isActive: true
        )

        // 既存テンプレートに追加して保存
        var templates = loadExistingTemplates()
        templates.append(template)
        saveTemplates(templates)

        // UIから除外
        dismissed.insert(pattern.id)
        saveDismissed(dismissed)

        registeredAlert = "「\(template.title)」を固定費に登録しました（毎月\(pattern.medianDay)日）"
    }

    private func dismissPattern(_ pattern: RecurringExpenseDetector.DetectedPattern) {
        withAnimation {
            dismissed.insert(pattern.id)
        }
        saveDismissed(dismissed)
    }

    // MARK: - 永続化

    private func loadExistingTemplates() -> [FixedExpenseTemplate] {
        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: [DataStore.fixedTemplatesKey])
        let data = defaults.migratedData(forKey: DataStore.fixedTemplatesKey) ?? Data()
        return (try? JSONDecoder().decode([FixedExpenseTemplate].self, from: data)) ?? []
    }

    private func saveTemplates(_ templates: [FixedExpenseTemplate]) {
        let data = try? JSONEncoder().encode(templates)
        UserDefaults.appGroup.set(data, forKey: DataStore.fixedTemplatesKey)
    }

    /// 一度スキップしたパターンのキーを保存（カテゴリID+金額概算）
    private static let dismissedKey = "kakebo.recurring.dismissed"

    private static func loadDismissed() -> Set<UUID> {
        // 単純にセッション内でのみ有効（パターンIDは毎回変わるため）
        // 代わりにカテゴリ+金額ベースで永続スキップを管理
        return []
    }

    private func saveDismissed(_ ids: Set<UUID>) {
        // セッション内でのみ有効
    }
}

// MARK: - パターン行

private struct PatternRow: View {
    let pattern: RecurringExpenseDetector.DetectedPattern
    let onRegister: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ヘッダー
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(pattern.memo.isEmpty ? pattern.categoryName : pattern.memo)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(pattern.categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(currency(pattern.averageAmount))
                    .font(.headline.weight(.bold).monospacedDigit())
            }

            // 詳細情報
            HStack(spacing: 12) {
                Label("毎月\(pattern.medianDay)日頃", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(pattern.monthsDetected)ヶ月連続", systemImage: "repeat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                confidenceBadge
            }

            // 金額推移（ミニバー）
            if pattern.recentAmounts.count >= 2 {
                AmountTrendMini(amounts: pattern.recentAmounts)
                    .frame(height: 20)
            }

            // アクションボタン
            HStack(spacing: 12) {
                Button {
                    onRegister()
                } label: {
                    Label("固定費に登録", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button {
                    onDismiss()
                } label: {
                    Text("スキップ")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var confidenceBadge: some View {
        let level: (String, Color) = {
            if pattern.confidence >= 0.8 { return ("高", .green) }
            if pattern.confidence >= 0.6 { return ("中", .orange) }
            return ("低", .gray)
        }()
        Text("確度: \(level.0)")
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(level.1.opacity(0.15))
            )
            .foregroundStyle(level.1)
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}

// MARK: - 金額推移ミニグラフ

private struct AmountTrendMini: View {
    let amounts: [Int]

    var body: some View {
        let maxVal = Double(amounts.max() ?? 1)
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(amounts.enumerated()), id: \.offset) { _, amount in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.blue.opacity(0.5))
                        .frame(width: 12, height: max(4, geo.size.height * (Double(amount) / maxVal)))
                }
            }
        }
    }
}
