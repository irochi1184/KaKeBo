import SwiftUI

struct EntryView: View {
    @ObservedObject var ledger: Ledger
    let onSave: (Voucher) -> Void
    @Environment(\.dismiss) private var dismiss
    @State var kind: Kind
    @State var date: Date
    @State private var amount = ""
    @State private var category: LedgerCategory?
    @State private var memo = ""
    @State private var picker = false
    @State private var error: String?
    @FocusState private var moneyFocused: Bool

    init(ledger: Ledger, kind: Kind, date: Date, onSave: @escaping (Voucher) -> Void) {
        self.ledger = ledger
        self.onSave = onSave
        _kind = State(initialValue: kind)
        _date = State(initialValue: date)
    }

    private var value: Int? {
        let trimmed = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 9, trimmed.allSatisfy({ $0.isNumber }), let n = Int(trimmed), n > 0 else { return nil }
        return n
    }

    private var recent: [LedgerCategory] {
        let options = LedgerCategory.options(kind)
        let names = ledger.entries.filter { $0.kind == kind }.map(\.category) + options.map(\.name)
        var used = Set<String>()
        return names.compactMap { name -> LedgerCategory? in
            guard used.insert(name).inserted else { return nil }
            return options.first { $0.name == name }
        }.prefix(3).map { $0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("収支", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    HStack {
                        Text("¥")
                        TextField("0", text: $amount)
                            .keyboardType(.numberPad).focused($moneyFocused)
                            .accessibilityLabel("金額")
                    }.font(.largeTitle.bold()).foregroundStyle(Paper.ink)
                    Divider()
                    DatePicker("日付", selection: $date, displayedComponents: .date)
                    Divider()
                    HStack {
                        Text("カテゴリ")
                        Spacer()
                        Button("すべて（\(LedgerCategory.options(kind).count)）") {
                            moneyFocused = false
                            picker = true
                        }
                    }
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(recent) { item in
                                Button(item.name) { category = item; moneyFocused = false }
                                    .buttonStyle(.bordered)
                                    .tint(category?.id == item.id ? Paper.ink : .secondary)
                            }
                        }
                    }
                    if let category {
                        CategoryLabel(item: category).accessibilityLabel("選択中、" + category.name)
                    }
                    Divider()
                    TextField("メモ（任意）", text: $memo, axis: .vertical)
                }
                .padding(20).background(Paper.sheet, in: ReceiptEdge())
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Paper.desk)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    Button { save(again: false) } label: {
                        Text("保存する").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent)
                    Button("保存して続ける") { save(again: true) }
                }
                .disabled(value == nil || category == nil || !ledger.ready)
                .padding(.horizontal).padding(.vertical, 8).background(Paper.desk)
            }
            .navigationTitle("伝票を記録").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完了") { moneyFocused = false } }
            }
            .sheet(isPresented: $picker) {
                CategoryPicker(kind: kind, selected: category?.id) { category = $0 }
            }
            .onChange(of: kind) { _, _ in category = nil }
            .onAppear { moneyFocused = true }
            .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる") {}
            } message: { Text(error ?? "") }
        }
    }

    private func save(again: Bool) {
        guard let value, let category else { return }
        let item = Voucher(date: date, kind: kind, category: category.name, amount: value, memo: memo)
        do {
            try ledger.append(item)
            onSave(item)
            amount = ""
            memo = ""
            if again { moneyFocused = true } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}

private struct CategoryPicker: View {
    let kind: Kind
    let selected: String?
    let pick: (LedgerCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var size
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                let items = LedgerCategory.options(kind).filter { query.isEmpty || $0.name.localizedStandardContains(query) }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: size.isAccessibilitySize ? 1 : 2), spacing: 0) {
                    ForEach(items) { item in
                        Button {
                            pick(item)
                            dismiss()
                        } label: {
                            HStack(spacing: 4) {
                                CategoryLabel(item: item)
                                Spacer(minLength: 0)
                                Image(systemName: "checkmark").foregroundStyle(Paper.ink)
                                    .opacity(selected == item.id ? 1 : 0)
                            }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(selected == item.id ? .isSelected : [])
                            .overlay(alignment: .bottom) { Divider() }
                    }
                }.padding(.horizontal)
                if items.isEmpty { Text("該当するカテゴリがありません").foregroundStyle(.secondary).padding() }
            }
            .background(Paper.sheet).navigationTitle("カテゴリを選ぶ").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "カテゴリを検索")
            .toolbar { Button("閉じる") { dismiss() } }
        }.presentationDragIndicator(.visible)
    }
}
