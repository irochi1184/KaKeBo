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
        SimpleEntry(date: .now, payload: placeholderSnapshot())
    }
    
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: .now, payload: makeEntryPayload()))
    }
    
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let now = Date()
        var entries: [SimpleEntry] = []
        for i in 0..<5 {
            if let d = Calendar.current.date(byAdding: .hour, value: i, to: now) {
                entries.append(SimpleEntry(date: d, payload: makeEntryPayload(referenceDate: d)))
            }
        }
        let nextReload = nextMidnightPlus5m(from: now)
        let timeline = Timeline(entries: entries, policy: .after(nextReload))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let payload: WidgetSnapshot
}

struct MonthSummary {
    let income: Int
    let expense: Int
    var balance: Int { income - expense }
}

struct WidgetCalendarDay: Identifiable {
    let date: Date
    let expense: Int
    let income: Int
    let isCurrentMonth: Bool
    var id: Date { date }
}

struct WidgetCalendarSnapshot {
    let month: Date
    let days: [WidgetCalendarDay]
}

struct WidgetSnapshot {
    let summary: MonthSummary
    let expenseSlices: [WSlice]
    let calendar: WidgetCalendarSnapshot
}

// Storeから現在月の集計を作る
private func makeEntryPayload(referenceDate: Date = Date()) -> WidgetSnapshot {
    let store = WStore()
    let summary = makeMonthSummary(store: store, referenceDate: referenceDate)
    let slices = expenseSlicesThisMonth(store: store, referenceDate: referenceDate)
    let calendar = makeCalendarSnapshot(store: store, referenceDate: referenceDate)
    return WidgetSnapshot(summary: summary, expenseSlices: slices, calendar: calendar)
}

private func placeholderSnapshot() -> WidgetSnapshot {
    let summary = MonthSummary(income: 120000, expense: 80000)
    let month = Date()
    let days = (0..<42).compactMap { offset -> WidgetCalendarDay? in
        guard let day = Calendar.current.date(byAdding: .day, value: offset, to: startOfFirstWeek(for: month)) else { return nil }
        let isCurrent = Calendar.current.isDate(day, equalTo: month, toGranularity: .month)
        let expense = isCurrent && offset % 5 == 0 ? 3200 : 0
        let income = isCurrent && offset % 9 == 0 ? 8500 : 0
        return WidgetCalendarDay(date: day, expense: expense, income: income, isCurrentMonth: isCurrent)
    }
    let calendar = WidgetCalendarSnapshot(month: month, days: days)
    return WidgetSnapshot(summary: summary, expenseSlices: [], calendar: calendar)
}

private func makeMonthSummary(store: WStore, referenceDate: Date = Date()) -> MonthSummary {
    let cal = Calendar.current
    let start = cal.date(from: cal.dateComponents([.year, .month], from: referenceDate))!
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

private func makeCalendarSnapshot(store: WStore, referenceDate: Date = Date()) -> WidgetCalendarSnapshot {
    let cal = Calendar.current
    let month = cal.date(from: cal.dateComponents([.year, .month], from: referenceDate)) ?? referenceDate

    var expenseBuckets: [Date: Int] = [:]
    var incomeBuckets: [Date: Int] = [:]
    for tx in store.transactions {
        let day = cal.startOfDay(for: tx.date)
        if tx.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "expense" {
            expenseBuckets[day, default: 0] += tx.amount
        } else if tx.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "income" {
            incomeBuckets[day, default: 0] += tx.amount
        }
    }

    let start = startOfFirstWeek(for: month)
    let days: [WidgetCalendarDay] = (0..<42).compactMap { offset in
        guard let day = cal.date(byAdding: .day, value: offset, to: start) else { return nil }
        let dayKey = cal.startOfDay(for: day)
        let expense = expenseBuckets[dayKey] ?? 0
        let income = incomeBuckets[dayKey] ?? 0
        let isCurrent = cal.isDate(day, equalTo: month, toGranularity: .month)
        return WidgetCalendarDay(date: day, expense: expense, income: income, isCurrentMonth: isCurrent)
    }

    return WidgetCalendarSnapshot(month: month, days: days)
}

private func nextMidnightPlus5m(from: Date = Date()) -> Date {
    let cal = Calendar.current
    let startOfNextDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: from))!
    let nextReload = cal.date(byAdding: .minute, value: 5, to: startOfNextDay)!
    return nextReload
}

private func startOfFirstWeek(for month: Date) -> Date {
    let cal = Calendar.current
    let firstDay = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
    let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: firstDay)
    return cal.date(from: comps) ?? firstDay
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

struct WSlice: Identifiable {
    let id: UUID
    let name: String
    let value: Int
    let color: Color
}

// Removed unused widgetPalette

// Helper to build expense slices for current month
private func expenseSlicesThisMonth(store: WStore = WStore(), referenceDate: Date = Date()) -> [WSlice] {
    let catStore = WCategoryStore()
    let cal = Calendar.current
    let start = cal.date(from: cal.dateComponents([.year, .month], from: referenceDate))!
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
            case .systemLarge:
                largeLayout
            default:
                regularLayout
            }
        }
        .modifier(BackgroundModifier())
    }
    
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("今月の収支").font(.caption2).foregroundStyle(.secondary)
            if entry.payload.summary.income == 0 && entry.payload.summary.expense == 0 {
                Text("データがありません")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(currency(entry.payload.summary.balance))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(entry.payload.summary.balance >= 0 ? .green : .red)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel("今月の収支")
                    .accessibilityValue(currency(entry.payload.summary.balance))
                VStack(spacing: 4) {
                    pill(title: "支出", value: entry.payload.summary.expense, icon: "arrow.down.left.circle.fill", base: .red)
                    pill(title: "収入", value: entry.payload.summary.income, icon: "arrow.up.right.circle.fill", base: .green)
                }
            }
        }
        .padding(10)
    }

    private var regularLayout: some View {
        Group {
            if entry.payload.summary.income == 0 && entry.payload.summary.expense == 0 {
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
                    Text(currency(entry.payload.summary.balance))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(entry.payload.summary.balance >= 0 ? .green : .red)
                        .accessibilityLabel("今月の収支")
                        .accessibilityValue(currency(entry.payload.summary.balance))
                    HStack {
                        pill(title: "支出", value: entry.payload.summary.expense, icon: "arrow.down.left.circle.fill", base: .red)
                        pill(title: "収入", value: entry.payload.summary.income, icon: "arrow.up.right.circle.fill", base: .green)
                    }
                }
                .padding()
            }
        }
    }
    
    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthTitle(entry.payload.calendar.month))
                        .font(.headline.weight(.semibold))
                    Text("日付をタップすると、その日の家計簿を開きます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("今月の収支").font(.caption).foregroundStyle(.secondary)
                    Text(currency(entry.payload.summary.balance))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(entry.payload.summary.balance >= 0 ? .green : .red)
                        .accessibilityLabel("今月の収支")
                        .accessibilityValue(currency(entry.payload.summary.balance))
                }
            }

            weekdayHeader

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(entry.payload.calendar.days) { day in
                    dayCell(day)
                }
            }

            HStack(spacing: 8) {
                pill(title: "支出", value: entry.payload.summary.expense, icon: "arrow.down.left.circle.fill", base: .red)
                pill(title: "収入", value: entry.payload.summary.income, icon: "arrow.up.right.circle.fill", base: .green)
            }
        }
        .padding(10)
        .scaleEffect(0.75, anchor: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    
    // --- Added mediumLayout with donut chart ---
    private var mediumLayout: some View {
        HStack(alignment: .center, spacing: 10) {
            // Left: reuse compact info similar to small
            VStack(alignment: .leading, spacing: 6) {
                Text("今月の収支").font(.caption).foregroundStyle(.secondary)
                Text(currency(entry.payload.summary.balance))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(entry.payload.summary.balance >= 0 ? .green : .red)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                VStack(spacing: 4) {
                    pill(title: "支出", value: entry.payload.summary.expense, icon: "arrow.down.left.circle.fill", base: .red)
                    pill(title: "収入", value: entry.payload.summary.income, icon: "arrow.up.right.circle.fill", base: .green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Right: donut
            VStack(alignment: .center) {
                DonutView(slices: entry.payload.expenseSlices, lineWidth: 12)
                    .frame(width: 130, height: 130)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(3)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(reorderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 2)
    }

    private var reorderedWeekdaySymbols: [String] {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        let first = Calendar.current.firstWeekday - 1
        if first > 0 {
            let head = symbols[first...]
            let tail = symbols[..<first]
            return Array(head + tail)
        }
        return symbols
    }

    private func dayCell(_ day: WidgetCalendarDay) -> some View {
        let cal = Calendar.current
        let isToday = cal.isDateInToday(day.date)
        let number = cal.component(.day, from: day.date)
        let destination = deepLink(for: day.date)
        let expenseText = day.expense > 0 ? "-\(dayAmountText(day.expense))" : nil
        let incomeText = day.income > 0 ? "+\(dayAmountText(day.income))" : nil

        return Link(destination: destination) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(number)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(day.isCurrentMonth ? .primary : Color.secondary.opacity(0.55))
                    if isToday {
                        Spacer()
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                }
                HStack(spacing: 3) {
                    if day.expense > 0 {
                        Capsule()
                            .fill(Color.red.opacity(0.85))
                            .frame(width: 12, height: 4)
                    }
                    if day.income > 0 {
                        Capsule()
                            .fill(Color.green.opacity(0.85))
                            .frame(width: 12, height: 4)
                    }
                    if day.expense == 0 && day.income == 0 {
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: 10, height: 3)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let expenseText {
                        Text(expenseText)
                            .font(.system(size: 6, weight: .semibold))
                            .foregroundStyle(Color.red.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    if let incomeText {
                        Text(incomeText)
                            .font(.system(size: 6, weight: .semibold))
                            .foregroundStyle(Color.green.opacity(0.9))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    if day.expense == 0 && day.income == 0 {
                        Text("0")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(cellBackgroundColor(for: day, isToday: isToday))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isToday ? Color.accentColor.opacity(0.7) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .frame(height: 46)
        .opacity(day.isCurrentMonth ? 1.0 : 0.45)
    }

    private func cellBackgroundColor(for day: WidgetCalendarDay, isToday: Bool) -> Color {
        if isToday { return Color.accentColor.opacity(0.18) }
        if day.expense > 0 && day.income > 0 { return Color.secondary.opacity(0.14) }
        if day.expense > 0 { return Color.red.opacity(0.10) }
        if day.income > 0 { return Color.green.opacity(0.10) }
        return Color.secondary.opacity(0.04)
    }

    private func deepLink(for date: Date) -> URL {
        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        let dateString = f.string(from: date)
        return URL(string: "kakebo://calendar?date=\(dateString)") ?? URL(string: "kakebo://calendar")!
    }

    private func monthTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.calendar = .current
        f.dateFormat = "yyyy年 M月"
        return f.string(from: date)
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
    
    private func dayAmountText(_ n: Int) -> String {
        Self.dayAmountFormatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
    
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.numberStyle = .currency
        f.currencyCode = "JPY"
        return f
    }()
    
    private static let dayAmountFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
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
        .description("今月の支出/収入/収支やカレンダーを表示します。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
