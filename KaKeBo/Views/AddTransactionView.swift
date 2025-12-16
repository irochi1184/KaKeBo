//
//  Views/AddTransactionView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import UIKit
import CloudKit

struct AddTransactionView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var purchase: PurchaseManager
    
    // MARK: - States
    @State private var date: Date = Date()
    @State private var amount: Int = 0
    @State private var amountText: String = "0"
    @State private var type: TransactionType = .expense
    @State private var memo: String = ""
    @State private var selectedCategoryId: UUID?
    @State private var selectedSharedCategoryId: CKRecord.ID?

    @State private var tags: [String] = []
    @State private var tagInput: String = ""

    // キーボード／UI
    @State private var isKeyboardVisible = false
    @FocusState private var memoFocused: Bool
    @FocusState private var amountFieldFocused: Bool
    @FocusState private var tagFieldFocused: Bool
    @State private var showCustomKeypad = true
    @State private var keypadHeight: CGFloat = 0
    @StateObject private var kb = KeyboardHeightReader()
    @State private var showAddCategory = false
    @State private var showAddSharedCategory = false
    @State private var showPaywall = false

    @State private var showTemplateSaved = false
    @State private var templateSavedMessage = ""
    @State private var showTemplateError = false
    @State private var templateErrorMessage = ""
    
    // ★ レシートスキャン表示フラグ
    @State private var showReceiptScanner = false
    
    // MARK: - Prefill (レシートや外部から)
    init(
        defaultCategoryId: UUID? = nil,
        defaultAmount: Int? = nil,
        defaultDate: Date? = nil,
        defaultType: TransactionType = .expense,
        defaultMemo: String? = nil
    ) {
        _selectedCategoryId = State(initialValue: defaultCategoryId)
        _amount = State(initialValue: defaultAmount ?? 0)
        _amountText = State(initialValue: defaultAmount.map { String($0) } ?? "0")
        _date   = State(initialValue: defaultDate ?? Date())
        _type   = State(initialValue: defaultType)
        _memo   = State(initialValue: defaultMemo ?? "")
    }
    
    // ===== 小画面（SE2等）だけの調整値 =====
    private var isSmallPhone: Bool {
#if os(iOS)
        UIScreen.main.bounds.height <= 667
#else
        false
#endif
    }
    private var keypadScale: CGFloat { isSmallPhone ? 0.86 : 0.85 }
    private var keypadHeightRatio: CGFloat { isSmallPhone ? 0.30 : 0.33 }
    private var keypadLift: CGFloat { isSmallPhone ? 34 : 0 }
    private var extraButtonLift: CGFloat { isSmallPhone ? 100 : 10 }
    private var safeBottomInset: CGFloat {
        UIApplication.shared.activeKeyWindow?.safeAreaInsets.bottom ?? 0
    }
    private var prefersCustomKeypad: Bool { themeStore.theme.prefersCustomKeypad }
    private var keypadColor: Color { themeStore.theme.keypadColor(isIncome: type == .income) }

    // MARK: - Body
    var body: some View {
        let usesCustomKeypad = prefersCustomKeypad
        NavigationStack {
            contentScroll
                .background(bgGradient.ignoresSafeArea())
                .navigationTitle("新規追加")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }

            // カスタム電卓
                .safeAreaInset(edge: .bottom) {
                    if usesCustomKeypad && showCustomKeypad {
                        ZStack {
                            NumericKeypad(
                                amount: $amount,
                                maxDigits: 9,
                                style: .attached,
                                isIncome: type == .income,
                                baseColorOverride: keypadColor,
                                sizeScale: keypadScale,
                                preferredHeightRatio: keypadHeightRatio,
                                onHeightChange: { h in keypadHeight = h }
                            )
                            .padding(.bottom, safeBottomInset)
                        }
                        .offset(y: -keypadLift)
                    }
                }

            // 自作キーパッドの閉じる
                .overlay(alignment: .bottomTrailing) {
                    if usesCustomKeypad && showCustomKeypad {
                        CloseKeyboardButton { showCustomKeypad = false }
                            .padding(.trailing, 12)
                            .padding(.bottom,
                                     max(8, (keypadHeight - keypadLift) + extraButtonLift + safeBottomInset)
                            )
                    }
                }
            
            // システムキーボード時の閉じる
                .overlay(alignment: .bottomTrailing) {
                    if memoFocused && kb.height > 0 {
                        CloseKeyboardButton {
                            memoFocused = false
                            showCustomKeypad = false
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, 8 + safeBottomInset)
                        .animation(.easeInOut(duration: 0.2), value: kb.height)
                    }
                }
            
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isKeyboardVisible = true
                        showCustomKeypad = false
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isKeyboardVisible = false
                    }
                }
            
            // ★ レシートスキャンのシート
                .sheet(isPresented: $showReceiptScanner) {
                    NavigationStack {
                        ReceiptScanView { recognized in
                            // 解析してフィールドへ反映（ReceiptParser.swift を利用）
                            let r = ReceiptParser.parse(recognized)
                            if let v = r.total { amount = v }
                            if let d = r.date  { date   = d }
                            if let m = r.merchant, m.isEmpty == false {
                                // 既にメモがあれば追記、なければ置換
                                memo = memo.isEmpty ? m : "\(memo) \(m)"
                            }
                            if let hint = r.categoryHint {
                                if ledgerContext.isPersonal {
                                    if let cat = store.categories.first(where: { $0.name.contains(hint) }) {
                                        selectedCategoryId = cat.id
                                    }
                                } else if let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore),
                                          let cats = sharedLedgerStore.categoriesByLedger[ledger.id] {
                                    if let cat = cats.first(where: { $0.name.contains(hint) }) {
                                        selectedSharedCategoryId = cat.id
                                    }
                                }
                            }
                            // 金額編集しやすいよう自作キーパッドを出しておく
                            if usesCustomKeypad { showCustomKeypad = true }
                        }
                        .navigationTitle("レシート読み取り")
                    }
                }
                .onAppear {
                    if !usesCustomKeypad { showCustomKeypad = false }
                    amountText = amount == 0 ? "" : String(amount)
                }
                .onChange(of: usesCustomKeypad) { _, newValue in
                    if !newValue { showCustomKeypad = false; amountFieldFocused = false }
                }
                .onChange(of: amount) { _, newValue in
                    amountText = newValue == 0 ? "" : String(newValue)
                }
                .onChange(of: amountText) { _, newValue in
                    let filtered = newValue.filter { $0.isNumber }
                    if filtered != newValue { amountText = filtered }
                    if let val = Int(filtered) { amount = val } else { amount = 0 }
                }
                .alert("保存しました", isPresented: $showTemplateSaved) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(templateSavedMessage)
                }
                .alert("適用できません", isPresented: $showTemplateError) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text(templateErrorMessage)
                }
        }
    }
    
    // MARK: - 分割ビュー
    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 18) {
                metaSection.luxCard()
                
                if ledgerContext.isPersonal {
                    CategorySelector(
                        selectedCategoryId: $selectedCategoryId,
                        onTapAdd: {
                            showAddCategory = true
                        }
                    )
                    frequentTemplateSection
                        .luxCard()
                } else {
                    SharedCategorySelector(
                        selectedCategoryId: $selectedSharedCategoryId,
                        onTapAdd: {
                            showAddSharedCategory = true
                        }
                    )
                }
                
                // タグ
                VStack(alignment: .leading, spacing: 8) {
                    Text("タグ（任意）")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    if purchase.isPremiumActive {
                        // 入力フィールド（空白・カンマ・読点・# で確定）
                        HStack(spacing: 6) {
                            TextField("例：家族 個人 (最大8文字)", text: $tagInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .submitLabel(.done)
                                .focused($tagFieldFocused)
                                .onSubmit { commitTagInput() }
                                .onChange(of: tagInput) { _, newValue in
                                    // 8文字を超えたら自動でカット
                                    if newValue.count > 8 {
                                        tagInput = String(newValue.prefix(8))
                                    }
                                    // 区切り文字が来たら即確定
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
                                Button {
                                    commitTagInput()
                                } label: {
                                    Text("追加")
                                        .font(.subheadline.weight(.semibold))
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        
                        // 付与済みタグ（削除ボタン付）
                        if !tags.isEmpty {
                            TagListView(
                                tags: tags,
                                onRemove: { t in removeTag(t) }
                            )
                        }
                        
                        // 最近使ったタグ（直近5件・トグル式）
                        if !recentTags.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("最近使ったタグ")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                
                                SuggestedTagListView(
                                    suggestions: recentTags,
                                    isOn: { tags.contains($0) },
                                    onToggle: { t in toggleTag(t) }
                                )
                            }
                        }
                    } else {
                        LockedCustomSection(accent: themeStore.theme.accentColor(for: scheme)) {
                            showPaywall = true
                        }
                    }
                }
                .luxCard()
                .sheet(isPresented: $showPaywall) {
                    PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                        .presentationDetents([.large, .medium])
                        .presentationDragIndicator(.visible)
                }
                
                Spacer(minLength: showCustomKeypad ? (isSmallPhone ? 20 : 60) : 0)
            }
            .padding(.top, 12)
            .padding(.horizontal)
        }
        .background(themeStore.theme.backgroundColor(for: scheme))
        .sheet(isPresented: $showAddCategory) {
            NavigationStack {
                CategoryEditorView(category: nil) { newCat in
                    selectedCategoryId = newCat.id
                }
                .environmentObject(store)
                .navigationTitle("カテゴリ追加")
            }
        }
        .sheet(
            isPresented: $showAddSharedCategory,
            onDismiss: {
                // シートが閉じられたタイミングでカテゴリ再読込
                if let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore) {
                    Task {
                        await sharedLedgerStore.reloadCategories(for: ledger)
                    }
                }
            }
        ) {
            if let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore) {
                NavigationStack {
                    SharedCategoryEditorView(ledger: ledger) { newSharedCat in
                        // 共有用：CKRecord.ID を即選択状態にする
                        selectedSharedCategoryId = newSharedCat.id
                    }
                    .environmentObject(sharedLedgerStore)
                    .navigationTitle("カテゴリ追加")
                }
            } else {
                Text("共有家計簿が選択されていません")
                    .padding()
            }
        }

    }
    
    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            TypePillSelector(type: $type)
            
            // 日付
            VStack(alignment: .leading, spacing: 6) {
                JapaneseDatePickerRow(date: $date)
            }
            
            // 金額
            VStack(alignment: .leading, spacing: 6) {
                Text("金額").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                if prefersCustomKeypad {
                    HStack {
                        Spacer()
                        Text(currency(amount))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.secondary.opacity(0.1))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        memoFocused = false
                        tagFieldFocused = false
                        withAnimation(.easeInOut(duration: 0.2)) { if prefersCustomKeypad { showCustomKeypad = true } }
                    }
                    .accessibilityAddTraits(.isButton)
                } else {
                    TextField("0", text: $amountText)
                        .keyboardType(.numberPad)
                        .focused($amountFieldFocused)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .multilineTextAlignment(.trailing)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.secondary.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                }
            }
            
            // メモ
            VStack(alignment: .leading, spacing: 6) {
                Text("メモ（任意）")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("例：昼食／スタバ など", text: $memo)
                    .textFieldStyle(.plain)
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
                    .focused($memoFocused)
            }
        }
    }

    private var frequentTemplateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("よく使う取引", systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }

            if store.frequentTemplates.isEmpty {
                Text("金額やカテゴリを保存しておくと、次回からワンタップで呼び出せます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.frequentTemplates) { tpl in
                            FrequentTemplateChip(
                                template: tpl,
                                category: categoryForTemplate(tpl),
                                currencyFormatter: currency
                            )
                            .onTapGesture { applyFrequentTemplate(tpl) }
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.deleteFrequentTemplate(id: tpl.id)
                                } label: {
                                    Label("ショートカットを削除", systemImage: "trash")
                                }
                            }
                            .opacity(isTemplateUsable(tpl) ? 1 : 0.4)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Button {
                saveCurrentAsFrequentTemplate()
            } label: {
                Label("現在の内容をよく使う取引に登録", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    // MARK: - ヘルパ
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }

    private func saveCurrentAsFrequentTemplate() {
        guard ledgerContext.isPersonal else { return }
        guard
            let selId = selectedCategoryId,
            let chosen = store.categories.first(where: { $0.id == selId }),
            amount > 0
        else {
            templateErrorMessage = "金額とカテゴリを入力してから保存してください。"
            showTemplateError = true
            return
        }

        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayTitle = trimmedMemo.isEmpty ? chosen.name : trimmedMemo

        let tpl = FrequentTransactionTemplate(
            title: displayTitle,
            amount: amount,
            type: type,
            memo: trimmedMemo,
            categoryId: chosen.id,
            tags: tags
        )

        store.addFrequentTemplate(tpl)
        templateSavedMessage = "\(displayTitle) を保存しました。長押しで削除できます。"
        showTemplateSaved = true
    }

    private func applyFrequentTemplate(_ tpl: FrequentTransactionTemplate) {
        guard let _ = categoryForTemplate(tpl) else {
            templateErrorMessage = "対応するカテゴリが見つからないため適用できません。"
            showTemplateError = true
            return
        }
        selectedCategoryId = tpl.categoryId
        amount = tpl.amount
        type = tpl.type
        memo = tpl.memo
        tags = tpl.tags

        if prefersCustomKeypad { showCustomKeypad = true }
    }

    private func categoryForTemplate(_ tpl: FrequentTransactionTemplate) -> Category? {
        store.categories.first(where: { $0.id == tpl.categoryId })
    }

    private func isTemplateUsable(_ tpl: FrequentTransactionTemplate) -> Bool {
        categoryForTemplate(tpl) != nil
    }
    
    private var bgGradient: LinearGradient {
        let colors: [Color] = (scheme == .dark)
        ? [Color.black, Color(white: 0.15)]
        : [Color(white: 0.98), Color(white: 0.94)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    // MARK: - Toolbar（保存の横にカメラ）
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") { dismiss() }
        }
        // ★ カメラ（レシート読取）ボタン
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // キーボードを閉じてからスキャナへ
                memoFocused = false
                tagFieldFocused = false
                showCustomKeypad = false
                showReceiptScanner = true
            } label: {
                Label("レシート", systemImage: "doc.text.viewfinder")
            }
        }
        // 保存ボタン
        ToolbarItem(placement: .topBarTrailing) {
            let isEnabled = !(store.categories.isEmpty || amount == 0 || selectedCategoryId == nil)
            SaveButton(isEnabled: isEnabled, accent: themeStore.theme.accentColor(for: scheme)) {
                save()
            }
        }
    }
    
    private func save() {
        guard
            let selId = selectedCategoryId,
            let chosen = store.categories.first(where: { $0.id == selId }),
            amount > 0
        else { return }
        
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // ▼ 1. 個人用家計簿のとき（今まで通り）
        if ledgerContext.isPersonal {
            let tx = Transaction(
                date: date,
                amount: amount,
                type: type,
                memo: trimmedMemo,
                categoryId: chosen.id,
                tags: tags
            )
            store.addTransaction(tx)
            dismiss()
            return
        }
        
        // ▼ 2. 共有家計簿のとき（CloudKit に保存）
        if ledgerContext.isShared,
           let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore) {
            
            // 共有カテゴリが選ばれているか？
            guard
                let sharedCatId = selectedSharedCategoryId,
                let cats = sharedLedgerStore.categoriesByLedger[ledger.id],
                let sharedCat = cats.first(where: { $0.id == sharedCatId }),
                amount > 0
            else {
                // カテゴリ未選択 or 見つからない場合は、とりあえず未分類扱いで保存するならここで分岐しても良い
                return
            }
            
            let sharedType: SharedTransactionType = (type == .income) ? .income : .expense
            let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)
            
            Task {
                await sharedLedgerStore.addTransaction(
                    to: ledger,
                    amount: amount,
                    date: date,
                    type: sharedType,
                    memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                    category: sharedCat   // ← ちゃんと渡す！！
                )
                dismiss()
            }
            return
        }

        // 念のため：どちらでもない場合は何もしないで閉じる
        dismiss()
    }
    
    // MARK: - タグ周り
    private func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "　", with: " ") // 全角空白→半角
    }
    private func commitTagInput() {
        // 区切り文字で分割し、空要素を除外・重複除去
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
        
        // ★ 文字数制限（8文字まで）
        let limited = String(v.prefix(8))
        
        // 重複を防いで追加
        if !tags.contains(limited) {
            tags.append(limited)
        }
    }
    private func toggleTag(_ t: String) {
        let limited = String(t.prefix(8))
        if let i = tags.firstIndex(of: limited) {
            tags.remove(at: i)
        } else {
            if !tags.contains(limited) { tags.append(limited) }
        }
    }

    private func removeTag(_ t: String) {
        tags.removeAll { $0 == t }
    }
    
    // 直近5件の「最近使ったタグ」
    private var recentTags: [String] {
        let stream = store.transactions
            .flatMap { $0.tags.map { String($0.prefix(8)) } } // ★ 8文字に統一
            .reversed()
        
        var seen = Set<String>()
        var result: [String] = []
        for t in stream {
            if !seen.contains(t) {
                seen.insert(t)
                result.append(t)
            }
            if result.count >= 5 { break }
        }
        return result
    }
}

// MARK: - Buttons & Utils（既存）

struct SaveButton: View {
    let isEnabled: Bool
    let accent: Color
    let action: () -> Void
    
    var body: some View {
        if isEnabled {
            Button("保存", action: action)
                .buttonStyle(.borderedProminent)
                .tint(accent)
        } else {
            Button("保存", action: {})
                .buttonStyle(.bordered)
                .disabled(true)
        }
    }
}

struct CloseKeyboardButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("閉じる", systemImage: "keyboard.chevron.compact.down")
                .imageScale(.medium)
                .font(.body.weight(.semibold))
                .padding(.vertical, 9)
                .padding(.horizontal, 13)
                .frame(minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.14), radius: 12, y: 3)
    }
}

private extension UIApplication {
    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}

// ===== 共通：等間隔フロー配置レイアウト =====
struct FlowLayout<Data: RandomAccessCollection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let spacing: CGFloat
    let lineSpacing: CGFloat
    @ViewBuilder let content: (Data.Element) -> Content
    
    init(items: Data, spacing: CGFloat = 8, lineSpacing: CGFloat = 8, @ViewBuilder content: @escaping (Data.Element) -> Content) {
        self.items = items
        self.spacing = spacing
        self.lineSpacing = lineSpacing
        self.content = content
    }
    
    var body: some View {
        GeometryReader { geo in
            self.generate(in: geo.size)
        }
        .frame(minHeight: 0)
    }
    
    private func generate(in size: CGSize) -> some View {
        var x: CGFloat = 0
        var y: CGFloat = 0
        return ZStack(alignment: .topLeading) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
                    .fixedSize() // ★ 内在サイズを尊重（広がらない）
                    .alignmentGuide(.leading) { d in
                        // 次を置いたらはみ出す？ → 改行
                        if x + d.width > size.width {
                            x = 0
                            y += d.height + lineSpacing
                        }
                        let result = x
                        x += d.width + spacing // ★ 等間隔で進める
                        return result
                    }
                    .alignmentGuide(.top) { _ in y }
            }
        }
    }
}

// ===== 安定版：等間隔フローレイアウト（iOS 16+） =====
struct FlowTagLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                // 改行
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + lineHeight)
    }
    
    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout ()) {
        let width = bounds.width
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                // 改行
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size))
            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }
    }
}

// ===== よく使う取引用のチップ =====
private struct FrequentTemplateChip: View {
    let template: FrequentTransactionTemplate
    let category: Category?
    let currencyFormatter: (Int) -> String

    private var accent: Color {
        category?.color ?? .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: category?.symbolName ?? "tag")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(accent)
                    )
                Text(template.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Text(currencyFormatter(template.amount))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.primary)
                Text(template.type == .income ? "収入" : "支出")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(accent.opacity(0.16)))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.12))
        )
    }
}

// ===== タグチップ（1行固定・最大8文字・省略） =====
struct TagChip: View {
    let text: String
    var leadingIcon: Image? = nil
    var trailingIcon: Image? = nil
    var selected: Bool = false
    
    var body: some View {
        HStack(spacing: 6) {
            if let leadingIcon { leadingIcon.imageScale(.small) }
            Text(String(text.prefix(8)))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if let trailingIcon { trailingIcon.imageScale(.small) }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule().fill(selected ? Color.accentColor.opacity(0.18)
                           : Color.secondary.opacity(0.12))
        )
        .contentShape(Capsule())
        .fixedSize(horizontal: true, vertical: true) // ← 幅が内容にフィットして安定
    }
}

struct TagListView: View {
    let tags: [String]
    let onRemove: (String) -> Void
    
    var body: some View {
        FlowTagLayout(spacing: 8, lineSpacing: 8) {
            ForEach(tags, id: \.self) { t in
                TagChip(text: t, trailingIcon: Image(systemName: "xmark.circle.fill"))
                    .onTapGesture { onRemove(t) }  // チップ全体で削除
                    .accessibilityLabel("\(t) を削除")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.2), value: tags)
    }
}

struct SuggestedTagListView: View {
    let suggestions: [String]
    let isOn: (String) -> Bool
    let onToggle: (String) -> Void
    
    var body: some View {
        FlowTagLayout(spacing: 8, lineSpacing: 8) {
            ForEach(suggestions.map { String($0.prefix(8)) }, id: \.self) { t in
                let selected = isOn(t)
                TagChip(text: t,
                        leadingIcon: Image(systemName: selected ? "checkmark.circle.fill" : "plus.circle"),
                        selected: selected)
                .onTapGesture { onToggle(t) }
                .accessibilityLabel("\(t) を\(selected ? "外す" : "追加")")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
