//
//  Views/EditTransactionView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/10.
//

import SwiftUI

struct EditTransactionView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    
    // 元データ
    let transaction: Transaction
    
    // 編集ステート（Add と同構成）
    @State private var date: Date
    @State private var amount: Int
    @State private var type: TransactionType
    @State private var memo: String
    @State private var selectedCategoryId: UUID?
    
    // キーボード制御（Add と揃える）
    @State private var isKeyboardVisible = false
    @FocusState private var memoFocused: Bool
    @State private var showCustomKeypad = true          // ← 初期表示：自作キーパッド表示
    @State private var keypadHeight: CGFloat = 0        // ← 自作キーパッド高さ（閉じるボタン位置調整用）
    @StateObject private var kb = KeyboardHeightReader()
    @State private var showAddCategory = false
    
    init(transaction: Transaction) {
        self.transaction = transaction
        _date = State(initialValue: transaction.date)
        _amount = State(initialValue: transaction.amount)
        _type = State(initialValue: transaction.type)
        _memo = State(initialValue: transaction.memo)
        _selectedCategoryId = State(initialValue: transaction.categoryId)
    }
    
    var body: some View {
        NavigationStack {
            contentScroll
                .background(bgGradient.ignoresSafeArea())
                .navigationTitle("取引を編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                // ▼ “自作キーボード”を制御（isKeyboardVisible ではなく showCustomKeypad を見る）
                .safeAreaInset(edge: .bottom) {
                    if showCustomKeypad {
                        NumericKeypad(
                            amount: $amount,
                            maxDigits: 9,
                            style: .attached,
                            isIncome: type == .income,
                            sizeScale: 0.85,              // Add と同じ縮尺
                            preferredHeightRatio: 0.33,   // 画面高 1/3
                            onHeightChange: { h in keypadHeight = h }
                        )
                    }
                }
                // 自作キーボード右上に “閉じる”（ガラスボタン）
                .overlay(alignment: .bottomTrailing) {
                    if showCustomKeypad {
                        CloseKeyboardButton {
                            showCustomKeypad = false
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, keypadHeight + 8) // キーボードの“上”
                    }
                }
                // システムキーボード時の「閉じる」をツールバー無しで重ねる
                .overlay(alignment: .bottomTrailing) {
                    // メモにフォーカス & キーボードが出ている時のみ表示
                    if memoFocused && kb.height > 0 {
                        CloseKeyboardButton {
                            memoFocused = false       // ← システムKBを閉じる
                            showCustomKeypad = false  // ← 念のため自作も閉じる
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, 8) // “キーボードの上” に浮かせる
                        .animation(.easeInOut(duration: 0.2), value: kb.height)
                    }
                }
            // ▼ システムKBが出たら自作は閉じる（メモ編集などのとき）
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
        }
    }
    
    // MARK: - Sections
    
    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 18) {
                metaSection.luxCard()
                
                CategorySelector(
                    selectedCategoryId: $selectedCategoryId,
                    onTapAdd: { showAddCategory = true }
                )
                .environmentObject(store)
                
                Spacer(minLength: showCustomKeypad ? 60 : 0) // 電卓に重ならない余白（Add と同様）
            }
            .padding(.top, 12)
            .padding(.horizontal)
        }
        .sheet(isPresented: $showAddCategory) {
            NavigationStack {
                CategoryEditorView(category: (nil as Category?))
                    .environmentObject(store)
                    .navigationTitle("カテゴリ追加")
            }
        }
    }
    
    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 種別トグル
            TypePillSelector(type: $type)
            
            // 日付
            VStack(alignment: .leading, spacing: 6) {
                Text("日付")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $date, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 金額（疑似入力欄・タップで自作キーボード）
            VStack(alignment: .leading, spacing: 6) {
                Text("金額").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
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
                    // メモのフォーカスを外してシステムKBを閉じる → 自作キーパッドを出す
                    memoFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) { showCustomKeypad = true }
                }
                .accessibilityAddTraits(.isButton)
            }
            
            // メモ
            VStack(alignment: .leading, spacing: 6) {
                Text("メモ（任意）")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("例：昼食／スタバ など", text: $memo)
                    .textFieldStyle(.roundedBorder)
                    .focused($memoFocused)
            }
        }
    }
    
    // MARK: - 共通見た目
    
    private var bgGradient: LinearGradient {
        let colors: [Color] = (scheme == .dark)
        ? [Color.black, Color(white: 0.15)]
        : [Color(white: 0.98), Color(white: 0.94)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
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
            Button("保存") { save() }
                .buttonStyle(.borderedProminent)
                .disabled(store.categories.isEmpty || amount == 0 || selectedCategoryId == nil)
        }
    }
    
    // MARK: - Actions
    
    private func save() {
        guard let catId = selectedCategoryId else { return }
        var edited = transaction
        edited.date = date
        edited.amount = amount
        edited.type = type
        edited.memo = memo
        edited.categoryId = catId
        
        store.upsertTransaction(edited)
        dismiss()
    }
    
    private func performDelete() {
        store.deleteTransactions(with: [transaction.id])
        dismiss()
    }
}
