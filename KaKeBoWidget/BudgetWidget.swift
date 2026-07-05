//
//  BudgetWidget.swift
//  KaKeBoWidget
//
//  予算残額ウィジェット（ホーム画面・ロック画面対応）。
//  - 全体予算（無料）: 今月の総予算に対する残額をゲージ/テキストで表示
//  - カテゴリ選択（プレミアム）: 指定カテゴリの予算残額を表示
//  - ホーム画面 中サイズ: カテゴリ別の残額一覧（プレミアム）
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
    let colorHex: String
}

private func loadCategories() -> [BWCategory] {
    guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else { return [] }
    let url = base.appendingPathComponent("categories.json")
    guard let data = try? Data(contentsOf: url),
          let list = try? JSONDecoder().decode([BWCategory].self, from: data) else { return [] }
    return list
}

private func budgetColor(fromHex hex: String?) -> Color? {
    guard var s = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let val = Int(s, radix: 16) else { return nil }
    let r = Double((val >> 16) & 0xFF) / 255.0
    let g = Double((val >> 8) & 0xFF) / 255.0
    let b = Double(val & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
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

/// ホーム画面 中サイズで表示するカテゴリ別の予算状況
struct BudgetCategoryStat: Identifiable {
    let id: UUID
    let name: String
    let symbolName: String
    let colorHex: String
    let budget: Int
    let expense: Int

    var remaining: Int { budget - expense }
    var isOver: Bool { expense > budget }
    var ratio: Double { budget > 0 ? min(Double(expense) / Double(budget), 1.0) : 0 }
}

struct BudgetWidgetSnapshot {
    enum State {
        case active        // 通常表示
        case locked        // カテゴリ選択がプレミアム未加入
        case noBudget      // 予算未設定
    }

    let state: State
    let title: String       // 「予算」またはカテゴリ名
    let symbolName: String
    let colorHex: String?   // カテゴリ色（全体表示は nil → アクセント色）
    let budget: Int
    let expense: Int
    let isPremium: Bool
    let categoryStats: [BudgetCategoryStat]

    var remaining: Int { budget - expense }
    var isOver: Bool { budget > 0 && expense > budget }
    var ratio: Double { budget > 0 ? min(Double(expense) / Double(budget), 1.0) : 0 }
}

private func makeBudgetSnapshot(category: BudgetWidgetCategoryEntity?, referenceDate: Date) -> BudgetWidgetSnapshot {
    let ctx = currentMonthContext(now: referenceDate)
    let budgets = WBudgetStore().budgets.filter { $0.monthId == ctx.monthId && $0.isEnabled && $0.limitAmount > 0 }
    let expenses = WStore().transactions.filter {
        $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "expense" &&
        ctx.range.contains($0.date)
    }
    let categories = loadCategories()
    let premium = isPremiumUnlocked(now: referenceDate)

    func expenseAmount(of categoryId: UUID) -> Int {
        expenses.filter { $0.categoryId == categoryId }.reduce(0) { $0 + $1.amount }
    }

    // カテゴリ別の予算状況（消化率が高い順 = 危険な順）
    let stats: [BudgetCategoryStat] = budgets.compactMap { b in
        guard let cat = categories.first(where: { $0.id == b.categoryId }) else { return nil }
        return BudgetCategoryStat(
            id: b.categoryId,
            name: cat.name,
            symbolName: cat.symbolName,
            colorHex: cat.colorHex,
            budget: b.limitAmount,
            expense: expenseAmount(of: b.categoryId)
        )
    }.sorted { Double($0.expense) / Double(max(1, $0.budget)) > Double($1.expense) / Double(max(1, $1.budget)) }

    if let category {
        // 表示名などは保存時ではなく現在のカテゴリ情報を参照（改名・アイコン変更に追従）
        let cat = categories.first { $0.id == category.id }
        let name = cat?.name ?? category.name
        let symbol = cat?.symbolName ?? category.symbolName

        // カテゴリ別表示はプレミアム限定
        guard premium else {
            return BudgetWidgetSnapshot(state: .locked, title: name, symbolName: "lock.fill", colorHex: nil,
                                        budget: 0, expense: 0, isPremium: false, categoryStats: [])
        }
        let budget = budgets.first { $0.categoryId == category.id }?.limitAmount ?? 0
        let expense = expenseAmount(of: category.id)
        guard budget > 0 else {
            return BudgetWidgetSnapshot(state: .noBudget, title: name, symbolName: symbol, colorHex: cat?.colorHex,
                                        budget: 0, expense: expense, isPremium: true, categoryStats: stats)
        }
        return BudgetWidgetSnapshot(state: .active, title: name, symbolName: symbol, colorHex: cat?.colorHex,
                                    budget: budget, expense: expense, isPremium: true, categoryStats: stats)
    }

    // 全体予算（予算タブの全体サマリーと同じ集計: 有効な予算の合計 vs 月の総支出）
    let totalBudget = budgets.reduce(0) { $0 + $1.limitAmount }
    let totalExpense = expenses.reduce(0) { $0 + $1.amount }
    guard totalBudget > 0 else {
        return BudgetWidgetSnapshot(state: .noBudget, title: "予算", symbolName: "yensign.circle", colorHex: nil,
                                    budget: 0, expense: totalExpense, isPremium: premium, categoryStats: stats)
    }
    return BudgetWidgetSnapshot(state: .active, title: "予算", symbolName: "yensign.circle", colorHex: nil,
                                budget: totalBudget, expense: totalExpense, isPremium: premium, categoryStats: stats)
}

// MARK: - Provider

struct BudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: BudgetWidgetSnapshot
}

private func sampleSnapshot() -> BudgetWidgetSnapshot {
    BudgetWidgetSnapshot(
        state: .active, title: "予算", symbolName: "yensign.circle", colorHex: nil,
        budget: 100_000, expense: 62_500, isPremium: true,
        categoryStats: [
            BudgetCategoryStat(id: UUID(), name: "食費", symbolName: "fork.knife", colorHex: "#FF9500", budget: 40_000, expense: 34_000),
            BudgetCategoryStat(id: UUID(), name: "日用品", symbolName: "basket", colorHex: "#34C759", budget: 15_000, expense: 9_800),
            BudgetCategoryStat(id: UUID(), name: "交際費", symbolName: "person.2", colorHex: "#5856D6", budget: 20_000, expense: 8_200)
        ]
    )
}

struct BudgetProvider: AppIntentTimelineProvider {
    typealias Entry = BudgetEntry
    typealias Intent = BudgetWidgetConfigIntent

    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: .now, snapshot: sampleSnapshot())
    }

    func snapshot(for configuration: BudgetWidgetConfigIntent, in context: Context) async -> BudgetEntry {
        // ウィジェットギャラリーのプレビューにはサンプルを表示
        if context.isPreview {
            return BudgetEntry(date: .now, snapshot: sampleSnapshot())
        }
        return BudgetEntry(date: .now, snapshot: makeBudgetSnapshot(category: configuration.category, referenceDate: .now))
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
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
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

    // MARK: ホーム画面共通

    /// メインの予算表示（カテゴリ色または既定色）
    private var mainColor: Color {
        budgetColor(fromHex: snapshot.colorHex) ?? .accentColor
    }

    private var mainBarColor: Color {
        if snapshot.isOver { return .red }
        if snapshot.ratio > 0.8 { return .orange }
        return mainColor
    }

    /// 小サイズおよび中サイズ左側のメインコンテンツ
    @ViewBuilder
    private var homeMainContent: some View {
        switch snapshot.state {
        case .locked:
            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text("カテゴリ別の表示は\nプレミアム限定です")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .noBudget:
            VStack(spacing: 6) {
                Image(systemName: snapshot.symbolName)
                    .font(.title3)
                    .foregroundStyle(mainColor)
                Text("\(snapshot.title)の予算が\n未設定です")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Text("タップして設定")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(mainColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .active:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: snapshot.symbolName)
                        .font(.caption)
                        .foregroundStyle(mainColor)
                    Text(snapshot.title == "予算" ? "今月の予算" : snapshot.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Text(snapshot.isOver ? "超過" : "残り")
                    .font(.caption2)
                    .foregroundStyle(snapshot.isOver ? .red : .secondary)
                Text(currency(snapshot.isOver ? snapshot.expense - snapshot.budget : snapshot.remaining))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(snapshot.isOver ? .red : .primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                progressBar(ratio: snapshot.ratio, color: mainBarColor, height: 6)

                Text("\(currency(snapshot.expense)) / \(currency(snapshot.budget))")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
        }
    }

    private var smallLayout: some View {
        homeMainContent
    }

    private var mediumLayout: some View {
        HStack(spacing: 12) {
            homeMainContent
                .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            categoryListPane
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 中サイズ右側: カテゴリ別の残額一覧（プレミアム限定）
    @ViewBuilder
    private var categoryListPane: some View {
        if !snapshot.isPremium {
            VStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.secondary)
                Text("カテゴリ別の残額は\nプレミアム限定です")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if snapshot.categoryStats.isEmpty {
            Text("カテゴリ予算が\n未設定です")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 7) {
                ForEach(snapshot.categoryStats.prefix(4)) { stat in
                    categoryStatRow(stat)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func categoryStatRow(_ stat: BudgetCategoryStat) -> some View {
        let color = budgetColor(fromHex: stat.colorHex) ?? .accentColor
        let barColor: Color = stat.isOver ? .red : (stat.ratio > 0.8 ? .orange : color)
        return HStack(spacing: 6) {
            Image(systemName: stat.symbolName)
                .font(.caption2)
                .foregroundStyle(color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(stat.name)
                        .font(.caption2)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(stat.isOver ? "\(compactAmount(stat.expense - stat.budget))超過" : "残り\(compactAmount(stat.remaining))")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(stat.isOver ? .red : .secondary)
                        .lineLimit(1)
                }
                progressBar(ratio: stat.ratio, color: barColor, height: 4)
            }
        }
    }

    private func progressBar(ratio: Double, color: Color, height: CGFloat) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(color.gradient)
                    .frame(width: geo.size.width * min(CGFloat(ratio), 1.0), height: height)
            }
        }
        .frame(height: height)
    }

    // MARK: 円形（ロック画面）

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

    // MARK: 横長（ロック画面）

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

    /// コンパクト表示（1万以上は「2.5万」）
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
        .description("今月の予算の残額をホーム画面・ロック画面に表示します。カテゴリを選ぶとそのカテゴリだけの残額を表示できます（プレミアム）。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
