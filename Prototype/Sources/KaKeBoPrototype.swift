import SwiftUI
import Charts

@main
struct KaKeBoPrototype: App {
    @StateObject private var ledger = Ledger()
    var body: some Scene {
        WindowGroup {
            PrototypeHome(ledger: ledger)
                .preferredColorScheme(.light)
                .environment(\.locale, Locale(identifier: "ja_JP"))
                .tint(Paper.ink)
        }
    }
}

private struct Slice: Identifiable {
    let name: String
    let amount: Int
    let color: Color
    var id: String { name }
}

private struct PrototypeHome: View {
    @ObservedObject var ledger: Ledger
    @State private var month = Date()
    @State private var kind = Kind.expense
    @State private var showEntry = false
    @AppStorage("prototype.horizontalChart") private var bars = false
    @State private var newest: UUID?

    private var current: [Voucher] {
        ledger.entries.filter { $0.kind == kind && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    private var slices: [Slice] {
        let groups = Dictionary(grouping: current, by: \.category)
        return LedgerCategory.options(kind).compactMap { category -> Slice? in
            guard let items = groups[category.name] else { return nil }
            return Slice(name: category.name, amount: items.reduce(0) { $0 + $1.amount }, color: category.color)
        }.sorted { $0.amount == $1.amount ? $0.name < $1.name : $0.amount > $1.amount }
    }

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var calendarOpen = false
    @State private var calendarDay = Date()
    private let greens: [Color] = [
        Color(red: 0.14, green: 0.31, blue: 0.16), Color(red: 0.36, green: 0.51, blue: 0.27),
        Color(red: 0.55, green: 0.67, blue: 0.37), Color(red: 0.68, green: 0.75, blue: 0.48),
        Color(red: 0.77, green: 0.80, blue: 0.62), Color(red: 0.86, green: 0.86, blue: 0.80)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Text("KaKeBo").font(.system(size: 29, weight: .semibold, design: .serif))
                    HStack {
                        Spacer()
                        Menu {
                            Picker("収支", selection: $kind) {
                                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                            }
                            Picker("グラフ", selection: $bars) {
                                Text("円グラフ").tag(false); Text("横棒グラフ").tag(true)
                            }
                        } label: {
                            Bookmark().fill(Bookmark.gold).frame(width: 16, height: 24).frame(width: 44, height: 44)
                        }.accessibilityLabel("表示設定")
                    }
                }.padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Paper.desk)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 8) {
                            monthButton(-1)
                            Text(month, format: .dateTime.year().month(.wide))
                                .font(.custom("HiraMinProN-W6", size: 28, relativeTo: .title))
                            monthButton(1)
                        }.frame(maxWidth: .infinity)
                        NavigationLink { breakdownList } label: { chartPanel }
                            .buttonStyle(.plain).accessibilityHint("カテゴリ別内訳を開きます")
                        Perforation()
                        Text("最近の記録").font(.custom("HiraMinProN-W6", size: 19, relativeTo: .headline))
                        if let item = current.first {
                            VoucherStub(item: item, marked: item.id == newest)
                        } else { Text("この月の記録はありません").foregroundStyle(.secondary) }
                    }.padding(.horizontal, 17).padding(.vertical, 16)
                }
                Button { showEntry = true } label: {
                    Label("記録する", systemImage: "plus")
                }.buttonStyle(VoucherButtonStyle()).disabled(!ledger.ready)
                    .padding(.horizontal, 31).padding(.vertical, 16)
                Divider()
                HStack(spacing: 0) {
                    tabLabel("ホーム", "house.fill").accessibilityAddTraits(.isSelected)
                    Button { calendarOpen = true } label: { tabLabel("カレンダー", "calendar") }
                    NavigationLink { breakdownList } label: { tabLabel("レポート", "chart.bar") }
                    NavigationLink { VoucherList(items: ledger.entries, title: "履歴") } label: { tabLabel("履歴", "list.bullet.rectangle") }
                    tabLabel("予算", "yensign.circle").opacity(0.45).accessibilityLabel("予算、試作対象外")
                }.padding(.top, 7)
            }
            .foregroundStyle(Paper.ink)
            .background { PaperSurface().ignoresSafeArea() }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showEntry) {
                EntryView(ledger: ledger, kind: kind, date: Date()) { item in
                    kind = item.kind; month = item.date; newest = item.id
                }
            }
            .sheet(isPresented: $calendarOpen) {
                VStack {
                    DatePicker("日付", selection: $calendarDay, displayedComponents: .date).datePickerStyle(.graphical)
                    VoucherList(items: ledger.entries.filter { Calendar.current.isDate($0.date, inSameDayAs: calendarDay) }, title: "")
                    Button("閉じる") { calendarOpen = false }
                }.padding()
            }
            .alert("保存領域を確認してください", isPresented: Binding(get: { ledger.problem != nil }, set: { if !$0 { ledger.problem = nil } })) {
                Button("閉じる") {}
            } message: { Text(ledger.problem ?? "") }
        }
    }

    private func tabLabel(_ name: String, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(name).font(.caption2)
        }.frame(maxWidth: .infinity, minHeight: 44)
    }

    private var breakdownList: some View {
        List(slices) { slice in
            NavigationLink { VoucherList(items: current.filter { $0.category == slice.name }, title: slice.name) } label: {
                HStack { Text(slice.name); Spacer(); Text(Paper.yen(slice.amount)) }
            }
        }.navigationTitle("カテゴリ別内訳").toolbar(.visible, for: .navigationBar)
    }

    private func monthButton(_ step: Int) -> some View {
        Button {
            month = Calendar.current.date(byAdding: .month, value: step, to: month) ?? month
        } label: { Image(systemName: step < 0 ? "chevron.left" : "chevron.right").frame(width: 44, height: 44) }
        .accessibilityLabel(step < 0 ? "前の月" : "次の月")
    }

    private var chartPanel: some View {
        let all = slices
        let total = current.reduce(0) { $0 + $1.amount }
        var shown = Array(all.prefix(5))
        if !bars && all.count > 5 {
            shown.append(Slice(name: "その他", amount: all.dropFirst(5).reduce(0) { $0 + $1.amount }, color: .gray))
        }
        let legend = VStack(spacing: 8) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, slice in
                VStack(spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(greens[index]).frame(width: 10, height: 10)
                        Text(slice.name)
                        Spacer(minLength: 2)
                        Text(Paper.yen(slice.amount)).monospacedDigit()
                    }.font(.subheadline)
                    if bars {
                        ProgressView(value: Double(slice.amount), total: Double(all.first?.amount ?? 1)).tint(greens[index])
                    }
                }
            }
        }
        let summary = VStack(spacing: 3) {
            Text("今月の" + kind.rawValue).font(.caption)
            Text(Paper.yen(total)).font(.system(.title2, design: .serif).weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.55)
        }
        let ring = ZStack {
            if shown.isEmpty { Circle().strokeBorder(Paper.desk, lineWidth: 18) }
            else {
                Chart(Array(shown.enumerated()), id: \.element.id) { index, slice in
                    SectorMark(angle: .value("金額", slice.amount), innerRadius: .ratio(0.70))
                        .foregroundStyle(greens[index])
                }.accessibilityHidden(true)
            }
            summary.padding(.horizontal, 16)
        }.aspectRatio(1, contentMode: .fit)
        return Group {
            if bars {
                VStack(spacing: 12) { summary; legend }
            } else if typeSize.isAccessibilitySize {
                VStack { ring.frame(height: 175); legend }
            } else {
                HStack(spacing: 12) {
                    ring.containerRelativeFrame(.horizontal) { width, _ in min(200, (width - 46) * 0.47) }
                    legend.frame(maxWidth: .infinity)
                }
            }
        }.padding(.vertical, 12).frame(maxWidth: .infinity)
    }

}

private struct VoucherStub: View {
    let item: Voucher
    var marked = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(item.date, format: .dateTime.month().day()).foregroundStyle(.secondary)
                Text(item.category)
                Spacer()
                Text(Paper.yen(item.amount)).bold().monospacedDigit()
                if marked { Image(systemName: "checkmark.circle.fill").foregroundStyle(Paper.ink).accessibilityLabel("保存済み") }
            }
            if !item.memo.isEmpty { Text(item.memo).font(.subheadline) }
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .background { PaperSurface().clipShape(ReceiptEdge(stub: true)).shadow(color: .black.opacity(0.14), radius: 2, y: 3) }
    }
}

private struct VoucherList: View {
    let items: [Voucher]
    let title: String
    var body: some View {
        ScrollView {
            LazyVStack { ForEach(items.sorted { $0.date > $1.date }) { VoucherStub(item: $0) } }.padding()
        }.background(Paper.desk).navigationTitle(title).toolbar(.visible, for: .navigationBar)
    }
}
