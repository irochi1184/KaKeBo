//
//  Views/Settings/FixedExpenseEditorView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/18.
//

import SwiftUI

struct FixedExpenseEditorView: View {
    let initial: FixedExpenseTemplate?
    let categories: [Category]
    let onSave: (FixedExpenseTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var purchase: PurchaseManager
    
    @State private var title: String = ""
    @State private var amount: Int = 0
    @State private var dayOfMonth: Int = 0   // 0=月末
    @State private var categoryId: UUID? = nil
    @State private var memo: String = ""
    @State private var isActive: Bool = true
    @State private var tags: [String] = []
    @State private var tagInput: String = ""
    @FocusState private var tagFieldFocused: Bool
    @State private var showPaywall = false
    
    // UI用：金額テキスト（フォーマット & 入力受け）
    @State private var amountText: String = ""
    
    // カテゴリ選択シート
    @State private var showCategorySheet = false
    // 日付選択シート
    @State private var showDaySheet = false
    
    init(initial: FixedExpenseTemplate?, categories: [Category], onSave: @escaping (FixedExpenseTemplate) -> Void) {
        self.initial = initial
        self.categories = categories
        self.onSave = onSave
        if let t = initial {
            _title       = State(initialValue: t.title)
            _amount      = State(initialValue: t.amount)
            _dayOfMonth  = State(initialValue: t.dayOfMonth)
            _categoryId  = State(initialValue: t.categoryId)
            _memo        = State(initialValue: t.memo ?? "")
            _isActive    = State(initialValue: t.isActive)
            _tags        = State(initialValue: t.tags.map { String($0.prefix(8)) })
            _amountText  = State(initialValue: Self.currency(t.amount))
        } else {
            _categoryId  = State(initialValue: categories.first?.id)
            _amountText  = State(initialValue: "")
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    card {
                        labeledField("名称") {
                            TextField("家賃 / 駐車場 / 電気代 …", text: $title)
                                .textInputAutocapitalization(.none)
                        }
                        dividerHairline
                        labeledField("金額") {
                            HStack(spacing: 8) {
                                TextField("¥80,000", text: $amountText)
                                    .textInputAutocapitalization(.none)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .font(.title3.weight(.semibold))
                                    .monospacedDigit()
                                    .onChange(of: amountText) { _, new in
                                        let digits = new.filter(\.isNumber)
                                        amount = Int(digits) ?? 0
                                    }
                            }
                        }
                    }
                    
                    card {
                        Button {
                            showDaySheet = true
                        } label: {
                            rowButton(title: "支払日",
                                      subtitle: dayOfMonth == 0 ? "毎月・月末" : "毎月 \(dayOfMonth) 日",
                                      iconName: "calendar",
                                      trailing: "chevron.right")
                        }
                        dividerHairline
                        Button {
                            showCategorySheet = true
                        } label: {
                            rowButton(
                                title: "カテゴリ",
                                subtitle: selectedCategory?.name ?? "未選択",
                                iconView: AnyView(                              // ← AnyView で包む
                                    Group {
                                        if let c = selectedCategory {
                                            Circle().fill(c.color.opacity(0.16))
                                                .frame(width: 24, height: 24)
                                                .overlay(Image(systemName: c.symbolName).foregroundStyle(c.color))
                                        } else {
                                            Image(systemName: "tag").foregroundStyle(.secondary)
                                        }
                                    }
                                                 ),
                                trailing: "chevron.right"
                            )
                        }
                    }
                    
                    card {
                        labeledField("メモ（任意）") {
                            TextField("例：口座引き落とし / 請求書払い など", text: $memo)
                                .textInputAutocapitalization(.none)
                        }
                        dividerHairline
                        HStack {
                            Label("有効にする", systemImage: isActive ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Toggle("", isOn: $isActive).labelsHidden()
                        }
                        .padding(.vertical, 4)
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("タグ（任意）")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            if purchase.isPremiumActive {
                                HStack(spacing: 6) {
                                    TextField("例：家族 固定費 (最大8文字)", text: $tagInput)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .submitLabel(.done)
                                        .focused($tagFieldFocused)
                                        .onSubmit { commitTagInput() }
                                        .onChange(of: tagInput) { _, newValue in
                                            if newValue.count > 8 {
                                                tagInput = String(newValue.prefix(8))
                                            }
                                            if tagInput.contains(where: { " ,、　#".contains($0) }) {
                                                commitTagInput()
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(themeStore.theme.backgroundColor(for: scheme))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .stroke(.secondary.opacity(0.2), lineWidth: 1)
                                        )

                                    if !tagInput.isEmpty {
                                        Button("追加") { commitTagInput() }
                                            .buttonStyle(.borderedProminent)
                                    }
                                }

                                if !tags.isEmpty {
                                    TagListView(tags: tags) { t in removeTag(t) }
                                }
                            } else {
                                LockedCustomSection(accent: themeStore.theme.accentColor(for: scheme)) {
                                    showPaywall = true
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 8)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .background(gradientBG.ignoresSafeArea())
            .navigationTitle(initial == nil ? "固定費を追加" : "固定費を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SaveButton(
                        isEnabled: canSave,
                        accent: themeStore.theme.accentColor(for: scheme)
                    ) {
                        amountText = Self.currency(amount) // 仕上げで整形
                        if let t = currentTemplate() {
                            onSave(t)
                            dismiss()
                        }
                    }
                }
            }
            .sheet(isPresented: $showCategorySheet) { categoryPickerSheet }
            .sheet(isPresented: $showDaySheet) { dayPickerSheet }
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
            }
            .onAppear {
                // 初回にフォーマット整える
                if amount > 0 && amountText.isEmpty {
                    amountText = Self.currency(amount)
                }
            }
        }
    }
    
    // MARK: - Cards & Rows
    
    @ViewBuilder
    private func card<Content: View>(pad: CGFloat = 12, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(pad)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                    )
            )
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.06), radius: 14, y: 6)
    }
    
    private var dividerHairline: some View {
        Divider().opacity(0.6).padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func labeledField<Content: View>(
        _ title: String,
        @ViewBuilder field: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            field()
        }
    }
    
    @ViewBuilder
    private func rowButton(
        title: String,
        subtitle: String,
        iconName: String? = nil,
        iconView: AnyView? = nil,
        trailing: String? = nil
    ) -> some View {
        let accent = themeStore.theme.accentColor(for: scheme)
        HStack(spacing: 12) {
            if let iconView {
                iconView
            } else if let iconName {
                Image(systemName: iconName).foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(accent)
                Text(subtitle).font(.subheadline).foregroundStyle(accent)
            }
            Spacer()
            if let trailing {
                Image(systemName: trailing).foregroundStyle(accent)
            }
        }
        .contentShape(Rectangle())
    }
    
    // MARK: - Pickers in Sheets
    
    private var categoryPickerSheet: some View {
        NavigationStack {
            List(categories) { c in
                Button {
                    categoryId = c.id
                    showCategorySheet = false
                } label: {
                    HStack(spacing: 12) {
                        Circle().fill(c.color.opacity(0.16))
                            .frame(width: 28, height: 28)
                            .overlay(Image(systemName: c.symbolName).foregroundStyle(c.color))
                        Text(c.name)
                        Spacer()
                        if c.id == categoryId { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("カテゴリを選択")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("閉じる") { showCategorySheet = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private var dayPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("支払日", selection: $dayOfMonth) {
                    Text("月末").tag(0)
                    ForEach(1...31, id: \.self) { d in
                        Text("\(d) 日").tag(d)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxHeight: 180)
                
                Text(dayOfMonth == 0 ? "毎月の最終日に計上" : "毎月 \(dayOfMonth) 日に計上")
                    .font(.subheadline).foregroundStyle(.secondary)
                
                Spacer()
            }
            .padding()
            .navigationTitle("支払日を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("完了") { showDaySheet = false } } }
        }
        .presentationDetents([.height(300), .large])
    }
    
    // MARK: - Utils
    
    private var selectedCategory: Category? {
        guard let id = categoryId else { return nil }
        return categories.first(where: { $0.id == id })
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount > 0 && categoryId != nil
    }
    
    private func currentTemplate() -> FixedExpenseTemplate? {
        guard let cat = categoryId else { return nil }
        return FixedExpenseTemplate(
            id: initial?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            dayOfMonth: dayOfMonth,
            categoryId: cat,
            memo: memo.isEmpty ? nil : memo,
            isActive: isActive,
            tags: tags
        )
    }
    
    private var gradientBG: LinearGradient {
        let colors: [Color] = (scheme == .dark)
        ? [Color.black, Color(white: 0.12)]
        : [Color(white: 0.98), Color(white: 0.94)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    // 通貨整形（3桁区切り・円マーク）
    private static func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }

    private func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "　", with: " ")
    }

    private func commitTagInput() {
        let seps = CharacterSet(charactersIn: " ,、　#")
        let parts = normalized(tagInput)
            .components(separatedBy: seps)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else {
            tagInput = ""
            return
        }
        for p in parts { addTag(p) }
        tagInput = ""
    }

    private func addTag(_ t: String) {
        let v = normalized(t)
        guard !v.isEmpty else { return }
        let limited = String(v.prefix(8))
        if !tags.contains(limited) {
            tags.append(limited)
        }
    }

    private func removeTag(_ t: String) {
        tags.removeAll { $0 == t }
    }
}

private struct LockedCustomSection: View {
    let accent: Color
    let onTapUpgrade: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(accent)
                Text("プレミアムプランに加入で、タグの追加・編集が無制限に利用できます。")
                Spacer()
            }
            Button("プレミアムを確認") { onTapUpgrade() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .padding(8)
    }
}
