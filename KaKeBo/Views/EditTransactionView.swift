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
    
    // キーボード制御
    @State private var isKeyboardVisible = false
    @FocusState private var memoFocused: Bool
    
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
            // キーボードが見えていないときだけ電卓を表示（Add と同じ）
                .safeAreaInset(edge: .bottom) {
                    if !isKeyboardVisible {
                        NumericKeypad(amount: $amount, maxDigits: 9, style: .attached, isIncome: type == .income)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = true }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = false }
                }
        }
    }
    
    // MARK: - Sections
    
    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 18) {
                metaSection.luxCard()
                
                CategorySelector(selectedCategoryId: $selectedCategoryId)
                    .environmentObject(store)
                
                Spacer(minLength: 60) // 電卓に重ならない余白
            }
            .padding(.top, 12)
            .padding(.horizontal)
        }
    }
    
    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            TypePillSelector(type: $type)
            
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
    
    private var bgGradient: LinearGradient {
        let colors: [Color] = (scheme == .dark)
        ? [Color.black, Color(white: 0.15)]
        : [Color(white: 0.98), Color(white: 0.94)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") { dismiss() }
        }
        // 右上：削除
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
                performDelete()
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        
        // 右上：保存（削除とは別アイテム）
        ToolbarItem(placement: .topBarTrailing) {
            Button("保存") {
                save()
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.categories.isEmpty || amount == 0 || selectedCategoryId == nil)
        }
        // キーボード上バー
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("閉じる") { memoFocused = false }
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
        
        // 既存のユーティリティに合わせて更新
        store.upsertTransaction(edited)
        dismiss()
    }
    
    private func performDelete() {
        store.deleteTransactions(with: [transaction.id])
        dismiss()
    }
}
