//
//  KaKeBoWidget.swift
//  KaKeBoWidget
//
//  今月の「支出/収入/収支」を表示するシンプルなウィジェット。
//  - 小: 収支を大きく + 下に支出/収入のピル
//  - 中: タイトル/収支/支出/収入を余裕をもって表示
//

import WidgetKit
import SwiftUI

// MARK: - 軽量リーダ（Widget側だけに置く版）
// 既に共有モジュールがあればそれをimportしてOK。
// ここではウィジェットだけでも読める最小限を用意。
struct WTransaction: Decodable {
    let id: UUID
    let date: Date
    let amount: Int
    let type: String   // "expense" or "income"
    let categoryId: UUID
    let memo: String
}

struct WStore {
    let transactions: [WTransaction]
    
    init() {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else {
#if DEBUG
            print("❌ (Widget) AppGroup URL nil: \(AppGroup.id)")
#endif
            self.transactions = []
            return
        }
        let url = base.appendingPathComponent("transactions.json")
        do {
            let data = try Data(contentsOf: url)
            // Try 1: ISO8601
            let dec1 = JSONDecoder()
            dec1.dateDecodingStrategy = .iso8601
            if let list = try? dec1.decode([WTransaction].self, from: data) {
                self.transactions = list
#if DEBUG
                let cnt = self.transactions.count
                let dates = self.transactions.map { $0.date }.sorted()
                if let first = dates.first, let last = dates.last {
                    print("✅ (Widget) 読み込み成功: \(cnt)件 (\(first) ... \(last))")
                } else {
                    print("✅ (Widget) 読み込み成功: \(cnt)件")
                }
#endif
                return
            }
            // Try 2: default date decoding
            let dec2 = JSONDecoder()
            if let list = try? dec2.decode([WTransaction].self, from: data) {
                self.transactions = list
#if DEBUG
                let cnt = self.transactions.count
                let dates = self.transactions.map { $0.date }.sorted()
                if let first = dates.first, let last = dates.last {
                    print("✅ (Widget) 読み込み成功: \(cnt)件 (\(first) ... \(last))")
                } else {
                    print("✅ (Widget) 読み込み成功: \(cnt)件")
                }
#endif
                return
            }
            // Try 3: ISO8601 with fractional seconds
            let iso8601fs = ISO8601DateFormatter()
            iso8601fs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let dec3 = JSONDecoder()
            dec3.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let str = try container.decode(String.self)
                if let d = iso8601fs.date(from: str) { return d }
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
            }
            if let list = try? dec3.decode([WTransaction].self, from: data) {
                self.transactions = list
#if DEBUG
                let cnt = self.transactions.count
                let dates = self.transactions.map { $0.date }.sorted()
                if let first = dates.first, let last = dates.last {
                    print("✅ (Widget) 読み込み成功: \(cnt)件 (\(first) ... \(last))")
                } else {
                    print("✅ (Widget) 読み込み成功: \(cnt)件")
                }
#endif
                return
            }
            // If all attempts failed, throw to catch
            throw NSError(domain: "KaKeBoWidget", code: -1, userInfo: [NSLocalizedDescriptionKey: "All decoding strategies failed"])
        } catch {
#if DEBUG
            if (try? Data(contentsOf: url)) == nil {
                print("ℹ️ (Widget) transactions.json なし: \(url.path)")
            } else {
                print("⚠️ (Widget) transactions.json デコード失敗(全戦略): \(error.localizedDescription)")
                if let data = try? Data(contentsOf: url) {
                    let head = String(data: data.prefix(200), encoding: .utf8) ?? "<binary>"
                    print("📄 先頭ダンプ:\n\(head)")
                }
            }
#endif
            self.transactions = []
        }
    }
}

struct Provider: TimelineProvider {
    typealias Entry = SimpleEntry
    
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: .now, payload: MonthSummary(income: 120000, expense: 80000))
    }
    
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now, payload: makePayload()))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let now = Date()
        var entries: [SimpleEntry] = []
        for i in 0..<5 {
            if let d = Calendar.current.date(byAdding: .hour, value: i, to: now) {
                entries.append(SimpleEntry(date: d, payload: makePayload()))
            }
        }
        let nextReload = nextMidnightPlus5m(from: now)
        let timeline = Timeline(entries: entries, policy: .after(nextReload))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let payload: MonthSummary
}

struct MonthSummary {
    let income: Int
    let expense: Int
    var balance: Int { income - expense }
}

// Storeから現在月の集計を作る
private func makePayload() -> MonthSummary {
    let store = WStore()
    let cal = Calendar.current
    let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
    _ = cal.date(byAdding: .month, value: 1, to: start)!
    
    let tx = store.transactions.filter { cal.isDate($0.date, equalTo: start, toGranularity: .month) }
#if DEBUG
    print("ℹ️ (Widget) 今月対象トランザクション: \(tx.count)件 / 総数: \(store.transactions.count)件")
    let twoYearsAgo = Calendar.current.date(byAdding: .year, value: -2, to: Date())!
    let twoYearsLater = Calendar.current.date(byAdding: .year, value: 2, to: Date())!
    let veryOld = store.transactions.filter { $0.date < twoYearsAgo }.count
    let veryFuture = store.transactions.filter { $0.date > twoYearsLater }.count
    if veryOld > 0 || veryFuture > 0 {
        print("⚠️ (Widget) 異常日付: 過去2年以上=\(veryOld)件 / 未来2年以上=\(veryFuture)件")
    }
#endif
    let income = tx.filter { $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "income" }.reduce(0) { $0 + $1.amount }
    let expense = tx.filter { $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "expense" }.reduce(0) { $0 + $1.amount }
    return MonthSummary(income: income, expense: expense)
}

private func nextMidnightPlus5m(from: Date = Date()) -> Date {
    let cal = Calendar.current
    let startOfNextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: from))!
    let nextReload = cal.date(byAdding: .minute, value: 5, to: startOfNextDay)!
    return nextReload
}

// --- Lightweight category reader (Widget side) ---
private struct WCategory: Decodable, Identifiable {
    let id: UUID
    let name: String
    let symbolName: String
    let colorHex: String
}

private struct WCategoryStore {
    let categories: [UUID: WCategory]
    init() {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else {
            self.categories = [:]
            return
        }
        let url = base.appendingPathComponent("categories.json")
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([WCategory].self, from: data) {
            var dict: [UUID: WCategory] = [:]
            list.forEach { dict[$0.id] = $0 }
            self.categories = dict
        } else {
            self.categories = [:]
        }
    }
}

private func colorFromHex(_ hex: String) -> Color {
    // Expect formats like "#RRGGBB" or "RRGGBB"
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let val = Int(s, radix: 16) else { return .gray }
    let r = Double((val >> 16) & 0xFF) / 255.0
    let g = Double((val >> 8) & 0xFF) / 255.0
    let b = Double(val & 0xFF) / 255.0
    return Color(red: r, green: g, blue: b)
}

private struct WSlice: Identifiable {
    let id: UUID
    let name: String
    let value: Int
    let color: Color
}

// Removed unused widgetPalette

// Helper to build expense slices for current month
private func expenseSlicesThisMonth() -> [WSlice] {
    let store = WStore()
    let catStore = WCategoryStore()
    let cal = Calendar.current
    let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
    let expenseTx = store.transactions.filter {
        cal.isDate($0.date, equalTo: start, toGranularity: .month) &&
        $0.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "expense"
    }
    var byCat: [UUID: Int] = [:]
    for tx in expenseTx { byCat[tx.categoryId, default: 0] += tx.amount }
    let sorted = byCat.sorted { $0.value > $1.value }
    return sorted.enumerated().map { (idx, pair) in
        let cat = catStore.categories[pair.key]
        let name = cat?.name ?? "カテゴリ"
        let color = colorFromHex(cat?.colorHex ?? "")
        return WSlice(id: pair.key, name: name, value: pair.value, color: color)
    }
}

private func currency(_ n: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = ","
    return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
}

private struct BackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 17.0, *) {
                content.containerBackground(.background, for: .widget)
            } else {
                content.background(Color(.secondarySystemBackground))
            }
        }
    }
}

// --- Added DonutView for donut chart ---
private struct DonutView: View {
    let slices: [WSlice]
    let lineWidth: CGFloat
    
    private struct Arc: Identifiable {
        let id: UUID
        let start: CGFloat
        let end: CGFloat
        let color: Color
    }
    
    private var arcs: [Arc] {
        let total = max(1, slices.reduce(0) { $0 + $1.value })
        var acc: CGFloat = 0
        return slices.map { s in
            let frac = CGFloat(s.value) / CGFloat(total)
            let start = acc
            let end = acc + frac
            acc = end
            return Arc(id: s.id, start: start, end: end, color: s.color)
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.secondary.opacity(0.15), lineWidth: lineWidth)
                ForEach(arcs) { a in
                    Circle()
                        .trim(from: a.start, to: a.end)
                        .stroke(a.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
            .rotationEffect(.degrees(-90))
            
            // Simple legend for top 2 slices
            let top2 = Array(slices.prefix(3))
            VStack(spacing: 2) {
                ForEach(top2, id: \.id) { s in
                    HStack(spacing: 3) {
                        Circle().fill(s.color).frame(width: 6, height: 6)
                        Text(s.name).font(.system(size: 10, design: .default))
                        Spacer()
                        Text(currency(s.value)).font(.system(size: 10, design: .default)).monospacedDigit()
                    }
                }
                Text("・・・").font(.system(size: 6, design: .default))
            }
        }
    }
}

struct KaKeBoWidgetEntryView: View {
    var entry: SimpleEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            case .systemMedium:
                mediumLayout
            default:
                regularLayout
            }
        }
        .modifier(BackgroundModifier())
    }
    
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今月の収支").font(.caption2).foregroundStyle(.secondary)
            if entry.payload.income == 0 && entry.payload.expense == 0 {
                Text("データがありません")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(currency(entry.payload.balance))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(entry.payload.balance >= 0 ? .green : .red)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel("今月の収支")
                    .accessibilityValue(currency(entry.payload.balance))
                VStack(spacing: 4) {
                    pill(title: "支出", value: entry.payload.expense, icon: "arrow.down.left.circle.fill", base: .red)
                    pill(title: "収入", value: entry.payload.income, icon: "arrow.up.right.circle.fill", base: .green)
                }
            }
        }
        .padding(10)
    }

    private var regularLayout: some View {
        Group {
            if entry.payload.income == 0 && entry.payload.expense == 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今月の収支").font(.caption).foregroundStyle(.secondary)
                    Text("データがありません")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("今月の収支").font(.caption).foregroundStyle(.secondary)
                    Text(currency(entry.payload.balance))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(entry.payload.balance >= 0 ? .green : .red)
                        .accessibilityLabel("今月の収支")
                        .accessibilityValue(currency(entry.payload.balance))
                    HStack {
                        pill(title: "支出", value: entry.payload.expense, icon: "arrow.down.left.circle.fill", base: .red)
                        pill(title: "収入", value: entry.payload.income, icon: "arrow.up.right.circle.fill", base: .green)
                    }
                }
                .padding()
            }
        }
    }
    
    // --- Added mediumLayout with donut chart ---
    private var mediumLayout: some View {
        HStack(alignment: .center, spacing: 10) {
            // Left: reuse compact info similar to small
            VStack(alignment: .leading, spacing: 6) {
                Text("今月の収支").font(.caption).foregroundStyle(.secondary)
                Text(currency(entry.payload.balance))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(entry.payload.balance >= 0 ? .green : .red)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                VStack(spacing: 4) {
                    pill(title: "支出", value: entry.payload.expense, icon: "arrow.down.left.circle.fill", base: .red)
                    pill(title: "収入", value: entry.payload.income, icon: "arrow.up.right.circle.fill", base: .green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: donut
            VStack(alignment: .center) {
                DonutView(slices: expenseSlicesThisMonth(), lineWidth: 12)
                    .frame(width: 130, height: 130)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(3)
    }
    
    private func pill(title: String, value: Int, icon: String, base: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(base.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(.secondary)
                Text(currency(value)).font(.caption.weight(.semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(base.opacity(0.12)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(currency(value))
    }
    
    private func currency(_ n: Int) -> String {
        Self.currencyFormatter.string(from: NSNumber(value: n)) ?? "¥\(n)"
    }
    
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.numberStyle = .currency
        f.currencyCode = "JPY"
        return f
    }()
}

struct KaKeBoWidget: Widget {
    let kind: String = "KaKeBoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            KaKeBoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("家計簿サマリー")
        .description("今月の支出/収入/収支を表示します。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
