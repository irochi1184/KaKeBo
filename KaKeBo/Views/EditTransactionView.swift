//
//  Views/EditTransactionView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/10.
//

import SwiftUI
import UIKit
import CloudKit

struct EditTransactionView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var purchase: PurchaseManager
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showPaywall = false
    
    enum Mode {
        case personal(Transaction)
        case shared(ledger: SharedLedger, transaction: SharedTransaction)
    }

    let mode: Mode

    // 元データ
    private var transaction: Transaction? {
        if case let .personal(tx) = mode { return tx }
        return nil
    }
    private var sharedContext: (ledger: SharedLedger, transaction: SharedTransaction)? {
        if case let .shared(ledger, tx) = mode { return (ledger, tx) }
        return nil
    }
    
    // 編集ステート（Add と同構成）
    @State private var date: Date
    @State private var amount: Int
    @State private var amountText: String
    @State private var type: TransactionType
    @State private var memo: String
    @State private var selectedCategoryId: UUID?
    @State private var selectedSharedCategoryId: CKRecord.ID?
    
    // ★ タグ（Add と同等）
    @State private var tags: [String]
    @State private var tagInput: String = ""

    // 添付写真（個人帳簿のみ・プレミアム機能）
    @State private var photoFilenames: [String]
    
    // キーボード制御（Add と揃える）
    @State private var isKeyboardVisible = false
    @FocusState private var memoFocused: Bool
    @FocusState private var amountFieldFocused: Bool
    @FocusState private var tagFieldFocused: Bool
    @State private var showCustomKeypad = true          // 初期表示：自作キーパッド表示
    @State private var keypadHeight: CGFloat = 0        // 自作キーパッド高さ（閉じるボタン位置調整用）
    @StateObject private var kb = KeyboardHeightReader()
    @State private var showAddCategory = false
    @State private var showAddSharedCategory = false

    init(transaction: Transaction) {
        self.mode = .personal(transaction)
        _date = State(initialValue: transaction.date)
        _amount = State(initialValue: transaction.amount)
        _amountText = State(initialValue: String(transaction.amount))
        _type = State(initialValue: transaction.type)
        _memo = State(initialValue: transaction.memo)
        _selectedCategoryId = State(initialValue: transaction.categoryId)
        _selectedSharedCategoryId = State(initialValue: nil)
        _tags = State(initialValue: transaction.tags.map { String($0.prefix(8)) }) // 8文字統一
        _photoFilenames = State(initialValue: transaction.photoFilenames ?? [])
    }

    init(sharedLedger: SharedLedger, transaction: SharedTransaction) {
        self.mode = .shared(ledger: sharedLedger, transaction: transaction)
        _date = State(initialValue: transaction.date)
        _amount = State(initialValue: transaction.amount)
        _amountText = State(initialValue: String(transaction.amount))
        _type = State(initialValue: transaction.type == .income ? .income : .expense)
        _memo = State(initialValue: transaction.memo ?? "")
        _selectedCategoryId = State(initialValue: nil)
        _selectedSharedCategoryId = State(initialValue: transaction.categoryId)
        _tags = State(initialValue: [])
        _photoFilenames = State(initialValue: [])
    }

    private var isSharedMode: Bool {
        sharedContext != nil
    }
    
    // 実効的に必要な下パディング（overlay配置のキーパッドと重ならないため）
    private var contentBottomPadding: CGFloat {
        guard prefersCustomKeypad && showCustomKeypad else { return 0 }
        // キーパッドの実高さ ー 見た目の持ち上げ量 + 余白 + セーフエリア
        return max(0, (keypadHeight - keypadLift)) + 16 + safeBottomInset
    }
    
    // ===== 小画面（SE2等）だけの調整値 =====
    private var isSmallPhone: Bool {
#if os(iOS)
        UIScreen.main.bounds.height <= 667
#else
        false
#endif
    }
    // AddTransactionView を参考に：サイズは少し大きめ、位置は上にずらす
    private var keypadScale: CGFloat { isSmallPhone ? 0.86 : 0.85 }       // 少し大きく
    private var keypadHeightRatio: CGFloat { isSmallPhone ? 0.30 : 0.33 } // 高さも戻す
    private var keypadLift: CGFloat { isSmallPhone ? 34 : 0 }             // 上方向に持ち上げ
    private var extraButtonLift: CGFloat { isSmallPhone ? 100 : 10 }      // 「閉じる」ボタンをさらに上へ
    
    // セーフエリア下端
    private var safeBottomInset: CGFloat {
        UIApplication.shared.activeKeyWindow?.safeAreaInsets.bottom ?? 0
    }
    private var keypadBackdropColor: Color {
        scheme == .dark
        ? Color(red: 0.08, green: 0.08, blue: 0.09)
        : Color(white: 0.98)
    }
    private var prefersCustomKeypad: Bool { themeStore.theme.prefersCustomKeypad }
    private var keypadColor: Color { themeStore.theme.keypadColor(isIncome: type == .income) }

    var body: some View {
        let usesCustomKeypad = prefersCustomKeypad
        NavigationStack {
            contentScroll
                .background(bgGradient.ignoresSafeArea())
                .navigationTitle("取引を編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
            // ▼ safeAreaInsetは使わず、overlayで下部配置（白抜け防止のため下地を敷く）
                .overlay(alignment: .bottom) {
                    if usesCustomKeypad && showCustomKeypad {
                        ZStack(alignment: .bottom) {
                            // 下地：透明領域でマテリアルが白発光するのを防ぐ
                            Rectangle()
                                .fill(keypadBackdropColor)
                                .frame(height: safeBottomInset + keypadLift + 24)
                                .ignoresSafeArea(edges: .bottom)

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
                            // ホームインジケータ分を確保した上で、見た目だけ上へ
                            .padding(.bottom, safeBottomInset)
                            .offset(y: -keypadLift)
                        }
                    }
                }
            // 右下・独立した「閉じる」ボタン（キーパッドの表示テキストに被らないよう高め）
                .overlay(alignment: .bottomTrailing) {
                    if usesCustomKeypad && showCustomKeypad {
                        CloseKeyboardButton {
                            showCustomKeypad = false
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, max(
                            8,
                            (keypadHeight - keypadLift) + extraButtonLift + safeBottomInset
                        ))
                    }
                }
            // システムキーボード時の「閉じる」をツールバー無しで重ねる
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
            // ▼ システムKBが出たら自作は閉じる（メモ/タグ編集などのとき）
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
        }
    }
    
    // MARK: - Sections
    
    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 18) {
                metaSection.luxCard()
                
                if isSharedMode {
                    SharedCategorySelector(
                        selectedCategoryId: $selectedSharedCategoryId,
                        onTapAdd: { showAddSharedCategory = true }
                    )
                    .environmentObject(sharedLedgerStore)
                    .environmentObject(ledgerContext)
                    .environmentObject(themeStore)
                    .environmentObject(purchase)
                } else {
                    CategorySelector(
                        selectedCategoryId: $selectedCategoryId,
                        onTapAdd: { showAddCategory = true }
                    )
                    .environmentObject(store)
                }

                if !isSharedMode {
                    // ===== タグ（Add と同等：8文字上限・最近5件・等間隔フロー） =====
                    VStack(alignment: .leading, spacing: 8) {
                        Text("タグ（任意）")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if purchase.isPremiumActive {
                            // 入力 + 追加
                            HStack(spacing: 6) {
                                TextField("例：家族 個人 (最大8文字)", text: $tagInput)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.done)
                                    .focused($tagFieldFocused)
                                    .onSubmit { commitTagInput() }
                                    .onChange(of: tagInput) { _, newValue in
                                        // 8文字超過は切り詰め
                                        if newValue.count > 8 {
                                            tagInput = String(newValue.prefix(8))
                                        }
                                        // 区切り文字で即確定
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

                            // 付与済みタグ（削除）
                            if !tags.isEmpty {
                                TagListView(
                                    tags: tags,
                                    onRemove: { t in removeTag(t) }
                                )
                            }

                            // 最近使ったタグ（直近5件・トグル）
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
                    }.luxCard()

                    // 写真添付（個人帳簿のみ・プレミアム機能）
                    TransactionPhotoSection(
                        photoFilenames: $photoFilenames,
                        accent: themeStore.theme.accentColor(for: scheme),
                        isPremium: purchase.isPremiumActive,
                        onRequirePremium: { showPaywall = true }
                    )
                    .luxCard()
                }

                Spacer(minLength: prefersCustomKeypad && showCustomKeypad ? (isSmallPhone ? 12 : 20) : 0)
            }
            .padding(.top, 12)
            .padding(.horizontal)
            // ← ここがポイント：キーパッド分だけスクロール領域に実パディングを付与
            .padding(.bottom, contentBottomPadding)
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
                if let ledger = sharedContext?.ledger {
                    Task {
                        await sharedLedgerStore.reloadCategories(for: ledger)
                    }
                }
            }
        ) {
            if let ledger = sharedContext?.ledger {
                NavigationStack {
                    SharedCategoryEditorView(ledger: ledger) { newCat in
                        selectedSharedCategoryId = newCat.id
                    }
                    .environmentObject(sharedLedgerStore)
                    .navigationTitle("カテゴリ追加")
                }
            } else {
                Text("共有家計簿が選択されていません")
                    .padding()
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 種別トグル
            TypePillSelector(type: $type)
            
            // 日付
            VStack(alignment: .leading, spacing: 6) {
                JapaneseDatePickerRow(date: $date)
            }
            
            // 金額（疑似入力欄・タップで自作キーボード）
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
                        // メモ/タグのフォーカスを外してシステムKBを閉じる → 自作キーパッドを出す
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
    
    // MARK: - 共通見た目
    
    private var bgGradient: LinearGradient {
        let isBusiness = themeStore.theme.visualStyle == .business
        let colors: [Color] = (scheme == .dark)
        ? [Color.black, isBusiness ? Color.black : Color(white: 0.15)]
        : [Color(white: 0.98), isBusiness ? Color(white: 0.98) : Color(white: 0.94)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }

    private var isSaveEnabled: Bool {
        switch mode {
        case .personal:
            return !(store.categories.isEmpty || amount == 0 || selectedCategoryId == nil)
        case let .shared(ledger, _):
            let cats = sharedLedgerStore.categoriesByLedger[ledger.id] ?? []
            return amount > 0 && !cats.isEmpty && selectedSharedCategoryId != nil
        }
    }

    // MARK: - Toolbar（Add と統一：削除と保存を独立して配置）
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
                performDelete()
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            SaveButton(isEnabled: isSaveEnabled, accent: themeStore.theme.accentColor(for: scheme)) {
                save()
            }
        }
    }
    
    // MARK: - タグ周り（Add と共通の実装）
    
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
        let v = String(normalized(t).prefix(8))
        guard !v.isEmpty else { return }
        if !tags.contains(v) { tags.append(v) }
    }
    private func toggleTag(_ t: String) {
        let v = String(t.prefix(8))
        if let i = tags.firstIndex(of: v) {
            tags.remove(at: i)
        } else if !tags.contains(v) {
            tags.append(v)
        }
    }
    private func removeTag(_ t: String) {
        tags.removeAll { $0 == t }
    }
    private var recentTags: [String] {
        // 新しい順 → 重複除去 → 先頭5件
        let stream = store.transactions
            .flatMap { $0.tags.map { String($0.prefix(8)) } }
            .reversed()
        var seen = Set<String>(), result: [String] = []
        for t in stream where !seen.contains(t) {
            seen.insert(t); result.append(t)
            if result.count >= 5 { break }
        }
        return result
    }
    
    // MARK: - Actions
    
    private func save() {
        let trimmedMemo = memo.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case let .personal(tx):
            guard let catId = selectedCategoryId else { return }
            var edited = tx
            edited.date = date
            edited.amount = amount
            edited.type = type
            edited.memo = trimmedMemo
            edited.categoryId = catId
            edited.tags = tags
            edited.photoFilenames = photoFilenames.isEmpty ? nil : photoFilenames

            store.upsertTransaction(edited)
            dismiss()

        case let .shared(ledger, sharedTx):
            let category = sharedLedgerStore.categoriesByLedger[ledger.id]?.first { $0.id == selectedSharedCategoryId }
            let sharedType: SharedTransactionType = (type == .income) ? .income : .expense

            guard amount > 0 else { return }

            Task {
                await sharedLedgerStore.updateTransaction(
                    sharedTx,
                    in: ledger,
                    amount: amount,
                    date: date,
                    type: sharedType,
                    memo: trimmedMemo.isEmpty ? nil : trimmedMemo,
                    category: category
                )
                dismiss()
            }
        }
    }

    private func performDelete() {
        switch mode {
        case let .personal(tx):
            store.deleteTransactions(with: [tx.id])
            dismiss()
        case let .shared(ledger, sharedTx):
            Task {
                await sharedLedgerStore.deleteTransaction(sharedTx, from: ledger)
                dismiss()
            }
        }
    }
}

// UIWindow / セーフエリア取得のユーティリティ
private extension UIApplication {
    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
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
