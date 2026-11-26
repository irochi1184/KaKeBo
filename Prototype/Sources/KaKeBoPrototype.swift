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
    @State private var settings = false
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        monthButton(-1)
                        Spacer()
                        Text(month, format: .dateTime.year().month(.wide)).font(.title3.bold())
                        Spacer()
                        monthButton(1)
                    }
                    Picker("収支", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    chartPanel
                    NavigationLink("カテゴリ別内訳") {
                        List(slices) { slice in
                            NavigationLink {
                                VoucherList(items: current.filter { $0.category == slice.name }, title: slice.name)
                            } label: {
                                HStack { Text(slice.name); Spacer(); Text(Paper.yen(slice.amount)) }
                            }
                        }.navigationTitle("カテゴリ別内訳")
                    }
                    Divider()
                    HStack {
                        Text("最近の記録").font(.headline)
                        Spacer()
                        NavigationLink("履歴") { VoucherList(items: ledger.entries, title: "すべての履歴") }
                    }
                    ForEach(current.prefix(4)) { item in
                        VoucherStub(item: item, marked: item.id == newest)
                    }
                }.padding()
            }
            .background(Paper.desk)
            .navigationTitle("KaKeBo 試作").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button { settings = true } label: { Image(systemName: "gearshape").accessibilityLabel("表示設定") } }
            .safeAreaInset(edge: .bottom) {
                Button { showEntry = true } label: {
                    Label("記録する", systemImage: "plus").font(.headline).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!ledger.ready).padding().background(Paper.desk)
            }
            .sheet(isPresented: $showEntry) {
                EntryView(ledger: ledger, kind: kind, date: Date()) { item in
                    kind = item.kind
                    month = item.date
                    newest = item.id
                }
            }
            .confirmationDialog("ホームのカテゴリ別グラフ", isPresented: $settings, titleVisibility: .visible) {
                Button("円グラフ") { bars = false }
                Button("横棒グラフ") { bars = true }
                Button("閉じる", role: .cancel) {}
            }
            .alert("保存領域を確認してください", isPresented: Binding(get: { ledger.problem != nil }, set: { if !$0 { ledger.problem = nil } })) {
                Button("閉じる") {}
            } message: { Text(ledger.problem ?? "") }
        }
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
        var shown = Array(all.prefix(bars ? 5 : 3))
        if !bars && all.count > 3 {
            shown.append(Slice(name: "ほか\(all.count - 3)カテゴリ", amount: all.dropFirst(3).reduce(0) { $0 + $1.amount }, color: .gray))
        }
        return VStack(alignment: .leading, spacing: 12) {
            Text(kind.rawValue + "合計").font(.subheadline)
            Text(Paper.yen(total)).font(.largeTitle.bold()).monospacedDigit()
            if all.isEmpty {
                Text("この月の記録はありません").foregroundStyle(.secondary)
            } else if !bars {
                Chart(shown) { slice in
                    SectorMark(angle: .value("金額", slice.amount), innerRadius: .ratio(0.68))
                        .foregroundStyle(slice.color)
                }.frame(height: 150).accessibilityHidden(true)
            }
            ForEach(shown) { slice in
                VStack(spacing: 3) {
                    HStack {
                        Circle().fill(slice.color).frame(width: 9, height: 9)
                        Text(slice.name)
                        Spacer()
                        Text(Paper.yen(slice.amount)).monospacedDigit()
                    }
                    if bars {
                        ProgressView(value: Double(slice.amount), total: Double(all.first?.amount ?? 1))
                            .tint(slice.color)
                    }
                }
            }
        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Paper.sheet)
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
        }.padding().background(Paper.sheet, in: ReceiptEdge())
    }
}

private struct VoucherList: View {
    let items: [Voucher]
    let title: String
    var body: some View {
        ScrollView {
            LazyVStack { ForEach(items.sorted { $0.date > $1.date }) { VoucherStub(item: $0) } }.padding()
        }.background(Paper.desk).navigationTitle(title)
    }
}
