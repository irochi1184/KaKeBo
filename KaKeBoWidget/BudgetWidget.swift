//
//  BudgetWidget.swift
//  KaKeBoWidget
//
//  ロック画面向けの予算残額ウィジェット。
//  - 全体予算（無料）: 今月の総予算に対する残額をゲージ/テキストで表示
//  - カテゴリ選択（プレミアム）: 指定カテゴリの予算残額を表示
//  月の範囲はアプリのカスタム月開始日設定（MonthStartResolver）に従う。
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - 軽量リーダ（予算）

struct WBudget: Decodable {
    let monthId: String
    let categoryId: UUID
    let limitAmount: Int
    let isEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case monthId, categoryId, limitAmount, isEnabled
    }

    // 旧データ（isEnabled キーなし）との後方互換
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthId = try c.decode(String.self, forKey: .monthId)
        categoryId = try c.decode(UUID.self, forKey: .categoryId)
        limitAmount = try c.decode(Int.self, forKey: .limitAmount)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}

struct WBudgetStore {
    let budgets: [WBudget]

    init() {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else {
            self.budgets = []
            return
        }
        let url = base.appendingPathComponent("budgets.json")
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([WBudget].self, from: data) {
            self.budgets = list
        } else {
            self.budgets = []
        }
    }
}

// MARK: - 軽量リーダ（カテゴリ）

private struct BWCategory: Decodable {
    let id: UUID
    let name: String
    let symbolName: String
}

private func loadCategories() -> [BWCategory] {
    guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else { return [] }
    let url = base.appendingPathComponent("categories.json")
    guard let data = try? Data(contentsOf: url),
          let list = try? JSONDecoder().decode([BWCategory].self, from: data) else { return [] }
    return list
}

// MARK: - 月範囲（カスタム月開始日を考慮）

private func currentMonthContext(now: Date) -> (monthId: String, range: Range<Date>) {
    let settings: MonthStartSettings = {
        guard let ud = UserDefaults(suiteName: AppGroup.id),
              let data = ud.data(forKey: "kakebo.monthStart.settings"),
              let s = try? JSONDecoder().decode(MonthStartSettings.self, from: data) else { return .default }
        return s
    }()
    let resolver = MonthStartResolver(settings: settings, holidayProvider: JapaneseHolidayProvider())
    let anchor = resolver.anchorMonth(containing: now)
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "yyyy-MM"
    return (f.string(from: anchor), resolver.monthRange(for: anchor))
}

// MARK: - プレミアム判定（AppGroup キャッシュ）

/// 課金キャッシュ（PurchaseManager が書き込む）または招待体験の期限から判定する
private func isPremiumUnlocked(now: Date = Date()) -> Bool {
    guard let ud = UserDefaults(suiteName: AppGroup.id) else { return false }
    if ud.bool(forKey: "premium.purchasedCache") { return true }
    let trialUntil = ud.double(forKey: "premium.referralTrial.until")
    return trialUntil > 0 && Date(timeIntervalSinceReferenceDate: trialUntil) > now
}

// MARK: - カテゴリ選択の AppIntent

struct BudgetWidgetCategoryEntity: AppEntity {
    let id: UUID
    let name: String
    let symbolName: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "カテゴリ"
    static var defaultQuery = BudgetWidgetCategoryQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct BudgetWidgetCategoryQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [BudgetWidgetCategoryEntity] {
        allEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BudgetWidgetCategoryEntity] {
        allEntities()
    }

    private func allEntities() -> [BudgetWidgetCategoryEntity] {
        loadCategories().map { BudgetWidgetCategoryEntity(id: $0.id, name: $0.name, symbolName: $0.symbolName) }
    }
}

struct BudgetWidgetConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "予算ウィジェット設定" }
    static var description: IntentDescription {
        IntentDescription("表示する予算を選べます。未選択の場合は今月の全体予算を表示します。カテゴリ別の表示はプレミアム限定です。")
    }

    @Parameter(title: "カテゴリ（プレミアム）")
    var category: BudgetWidgetCategoryEntity?
}

// MARK: - スナップショット

struct BudgetWidgetSnapshot {
    enum State {
        case active        // 通常表示
        case locked        // カテゴリ選択がプレミアム未加入
        case noBudget      // 予算未設定
    }

    let state: State
    let title: String       // 「予算」またはカテゴリ名
    let symbolName: String
    let budget: Int
    let expense: Int

    var remaining: Int { budget - expense }
    var isOver: Bool { budget > 0 && expense > budget }
    var ratio: Double { budget > 0 ? min(Double(expense) / Double(budget), 1.0) : 0 }
}

private func makeBudgetSnapshot(category: BudgetWidgetCategoryEntity?, referenceDate: Date) -> BudgetWidgetSnapshot {
    let ctx = currentMonthContext(now: referenceDate)
    let budgets = WBudgetStore().budgets.filter { $0.monthId == ctx.monthId && $0.isEnabled }
    let expenses = WStore().transactions.filter {
        $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "expense" &&
        ctx.range.contains($0.date)
    }

    if let category {
        // カテゴリ別表示はプレミアム限定
        guard isPremiumUnlocked(now: referenceDate) else {
            return BudgetWidgetSnapshot(state: .locked, title: category.name, symbolName: "lock.fill", budget: 0, expense: 0)
        }
        let budget = budgets.first { $0.categoryId == category.id }?.limitAmount ?? 0
        let expense = expenses.filter { $0.categoryId == category.id }.reduce(0) { $0 + $1.amount }
        guard budget > 0 else {
            return BudgetWidgetSnapshot(state: .noBudget, title: category.name, symbolName: category.symbolName, budget: 0, expense: expense)
        }
        return BudgetWidgetSnapshot(state: .active, title: category.name, symbolName: category.symbolName, budget: budget, expense: expense)
    }

    // 全体予算（予算タブの全体サマリーと同じ集計: 有効な予算の合計 vs 月の総支出）
    let totalBudget = budgets.reduce(0) { $0 + $1.limitAmount }
    let totalExpense = expenses.reduce(0) { $0 + $1.amount }
    guard totalBudget > 0 else {
        return BudgetWidgetSnapshot(state: .noBudget, title: "予算", symbolName: "yensign.circle", budget: 0, expense: totalExpense)
    }
    return BudgetWidgetSnapshot(state: .active, title: "予算", symbolName: "yensign.circle", budget: totalBudget, expense: totalExpense)
}

// MARK: - Provider

struct BudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BudgetWidgetSnapshot
}

struct BudgetProvider: AppIntentTimelineProvider {
    typealias Entry = BudgetEntry
    typealias Intent = BudgetWidgetConfigIntent

    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: .now, snapshot: BudgetWidgetSnapshot(
            state: .active, title: "予算", symbolName: "yensign.circle", budget: 100_000, expense: 62_500
        ))
    }

    func snapshot(for configuration: BudgetWidgetConfigIntent, in context: Context) async -> BudgetEntry {
        BudgetEntry(date: .now, snapshot: makeBudgetSnapshot(category: configuration.category, referenceDate: .now))
    }

    func timeline(for configuration: BudgetWidgetConfigIntent, in context: Context) async -> Timeline<BudgetEntry> {
        let now = Date()
        var entries: [BudgetEntry] = []
        for i in 0..<5 {
            if let d = Calendar.current.date(byAdding: .hour, value: i, to: now) {
                entries.append(BudgetEntry(date: d, snapshot: makeBudgetSnapshot(category: configuration.category, referenceDate: d)))
            }
        }
        // 日付が変わったら（月替わり対応で）確実に再計算する
        let cal = Calendar.current
        let startOfNextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let nextReload = cal.date(byAdding: .minute, value: 5, to: startOfNextDay) ?? now
        return Timeline(entries: entries, policy: .after(nextReload))
    }
}

// MARK: - View

struct BudgetWidgetEntryView: View {
    var entry: BudgetEntry
    @Environment(\.widgetFamily) private var family

    private var snapshot: BudgetWidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circularLayout
            case .accessoryRectangular:
                rectangularLayout
            default:
                inlineLayout
            }
        }
        .widgetURL(URL(string: "kakebo://budget"))
        .containerBackground(.background, for: .widget)
    }

    // MARK: 円形

    @ViewBuilder
    private var circularLayout: some View {
        switch snapshot.state {
        case .locked:
            VStack(spacing: 2) {
                Image(systemName: "lock.fill")
                Text("プレミアム")
                    .font(.system(size: 9, weight: .medium))
            }
        case .noBudget:
            VStack(spacing: 2) {
                Image(systemName: snapshot.symbolName)
                Text("予算未設定")
                    .font(.system(size: 8, weight: .medium))
                    .minimumScaleFactor(0.8)
            }
        case .active:
            Gauge(value: snapshot.ratio) {
                Text(snapshot.title.prefix(2))
                    .font(.system(size: 9, weight: .medium))
            } currentValueLabel: {
                Text(compactAmount(snapshot.remaining))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .minimumScaleFactor(0.7)
            }
            .gaugeStyle(.accessoryCircular)
        }
    }

    // MARK: 横長

    @ViewBuilder
    private var rectangularLayout: some View {
        switch snapshot.state {
        case .locked:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill").font(.caption2)
                    Text("カテゴリ別予算").font(.caption2).foregroundStyle(.secondary)
                }
                Text("プレミアム限定")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                Text("タップして詳細へ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .noBudget:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: snapshot.symbolName).font(.caption2)
                    Text(snapshot.title).font(.caption2).foregroundStyle(.secondary)
                }
                Text("予算未設定")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                Text("タップして設定")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .active:
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: snapshot.symbolName).font(.caption2)
                    Text("\(snapshot.title)・今月").font(.caption2).foregroundStyle(.secondary)
                }
                .widgetAccentable()
                Text(snapshot.isOver
                     ? "\(currency(snapshot.expense - snapshot.budget)) 超過"
                     : "残り \(currency(snapshot.remaining))")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Gauge(value: snapshot.ratio) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
        }
    }

    // MARK: インライン（時計上の1行）

    private var inlineLayout: some View {
        let text: String
        switch snapshot.state {
        case .locked:
            text = "カテゴリ予算はプレミアム限定"
        case .noBudget:
            text = "\(snapshot.title) 予算未設定"
        case .active:
            text = snapshot.isOver
                ? "\(snapshot.title) \(compactAmount(snapshot.expense - snapshot.budget))超過"
                : "\(snapshot.title) 残り\(compactAmount(snapshot.remaining))"
        }
        return Text(text)
    }

    // MARK: フォーマッタ

    /// ロック画面向けのコンパクト表示（1万以上は「2.5万」）
    private func compactAmount(_ n: Int) -> String {
        if abs(n) >= 10_000 {
            return String(format: "%.1f万", Double(n) / 10_000.0)
        }
        return "¥\(n)"
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}

// MARK: - Widget 定義

struct KaKeBoBudgetWidget: Widget {
    let kind: String = "KaKeBoBudgetWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: BudgetWidgetConfigIntent.self, provider: BudgetProvider()) { entry in
            BudgetWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("予算の残り")
        .description("今月の予算の残額を表示します。カテゴリを選ぶとそのカテゴリだけの残額を表示できます（プレミアム）。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
