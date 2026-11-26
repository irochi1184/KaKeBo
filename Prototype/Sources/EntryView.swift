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

    @FocusState private var memoFocused: Bool
    @State private var showDate = false
    private var chips: [LedgerCategory] {
        guard let category, !recent.contains(where: { $0.id == category.id }) else { return recent }
        return [category] + Array(recent.prefix(2))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Text("記録する").font(.custom("HiraMinProN-W6", size: 23, relativeTo: .title2))
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").frame(width: 44, height: 44)
                        }.accessibilityLabel("閉じる")
                        Spacer()
                    }
                }.padding(.horizontal, 10)
                ScrollView {
                    VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            ForEach(Kind.allCases) { choice in
                                Button {
                                    kind = choice
                                } label: {
                                    Text(choice.rawValue).frame(maxWidth: .infinity, minHeight: 37)
                                        .foregroundStyle(choice == kind ? .white : Paper.ink)
                                        .background(choice == kind ? Paper.ink : .clear, in: Capsule())
                                }.accessibilityAddTraits(choice == kind ? .isSelected : [])
                            }
                        }.frame(maxWidth: 235)
                            .overlay { Capsule().strokeBorder(Paper.ink.opacity(0.3), lineWidth: 0.7) }
                            .padding(.top, 29).padding(.bottom, 12)
                        field("金額") {
                            HStack(spacing: 2) {
                                Text("¥")
                                TextField("", text: $amount)
                                    .keyboardType(.numberPad).focused($moneyFocused)
                                    .accessibilityLabel("金額")
                            }.font(.system(size: 36, weight: .semibold, design: .serif))
                        }
                        Perforation()
                        field("日付") {
                            Button { moneyFocused = false; showDate = true } label: {
                                HStack {
                                    Text(date, format: .dateTime.month().day())
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption)
                                }.contentShape(Rectangle())
                            }
                        }
                        Perforation()
                        field("カテゴリ") {
                            VStack(alignment: .trailing, spacing: 5) {
                                ScrollView(.horizontal) {
                                    HStack(spacing: 6) {
                                        ForEach(chips) { item in
                                            Button {
                                                category = item; moneyFocused = false; memoFocused = false
                                            } label: {
                                                Text(item.name).font(.subheadline).fixedSize()
                                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                                    .foregroundStyle(category?.id == item.id ? .white : Paper.ink)
                                                    .background(category?.id == item.id ? Paper.ink : .clear, in: Capsule())
                                                    .overlay { Capsule().strokeBorder(Paper.ink.opacity(0.3), lineWidth: 0.6) }
                                            }
                                        }
                                    }
                                }.scrollIndicators(.hidden)
                                Button("すべて（\(LedgerCategory.options(kind).count)） ›") {
                                    moneyFocused = false; memoFocused = false; picker = true
                                }.font(.subheadline)
                            }
                        }
                        Perforation()
                        field("メモ") {
                            TextField("メモ（任意）", text: $memo, axis: .vertical).focused($memoFocused)
                        }.padding(.bottom, 14)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 17)
                    .background { PaperSurface().clipShape(ReceiptEdge()).shadow(color: .black.opacity(0.17), radius: 3, y: 4) }
                    .overlay(alignment: .topTrailing) {
                        Bookmark().fill(Bookmark.gold).frame(width: 20, height: 30).padding(.trailing, 22)
                            .allowsHitTesting(false)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }.scrollDismissesKeyboard(.interactively)
            }
            .foregroundStyle(Paper.ink)
            .background { PaperSurface(base: Paper.desk).ignoresSafeArea() }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button("保存する") { save(again: false) }.buttonStyle(VoucherButtonStyle(filled: true))
                    if value != nil && category != nil {
                        Button("保存して続ける") { save(again: true) }.buttonStyle(VoucherButtonStyle())
                    }
                }
                .disabled(value == nil || category == nil || !ledger.ready)
                .padding(.horizontal, 26).padding(.vertical, moneyFocused ? 5 : 14)
            }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完了") { moneyFocused = false; memoFocused = false }
                }
            }
            .sheet(isPresented: $picker) {
                CategoryPicker(kind: kind, selected: category?.id) { category = $0 }
            }
            .sheet(isPresented: $showDate) {
                VStack {
                    DatePicker("日付", selection: $date, displayedComponents: .date).datePickerStyle(.graphical)
                    Button("完了") { showDate = false }
                }.padding().presentationDetents([.medium])
            }
            .onChange(of: kind) { _, _ in category = nil }
            .task { moneyFocused = true }
            .alert("保存できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("閉じる") {}
            } message: { Text(error ?? "") }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).font(.subheadline).frame(width: 66, alignment: .leading)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 13)
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
