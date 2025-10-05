//
//  Views/AddTransactionView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme   // ← 追加
    
    @State private var date: Date = Date()
    @State private var amount: Int = 0
    @State private var type: TransactionType = .expense
    @State private var memo: String = ""
    @State private var selectedCategoryId: UUID?
    
    init(
        defaultCategoryId: UUID? = nil,
        defaultAmount: Int? = nil,
        defaultDate: Date? = nil,
        defaultType: TransactionType = .expense,
        defaultMemo: String? = nil
    ) {
        _selectedCategoryId = State(initialValue: defaultCategoryId)
        _amount = State(initialValue: defaultAmount ?? 0)
        _date   = State(initialValue: defaultDate ?? Date())
        _type   = State(initialValue: defaultType)
        _memo   = State(initialValue: defaultMemo ?? "")
    }
    
    var body: some View {
        NavigationStack {
            contentScroll
                .background(bgGradient.ignoresSafeArea())   // ← 重い式を外出し
                .navigationTitle("新規追加")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .safeAreaInset(edge: .bottom) { keypadBar } // ← これも外出し
        }
    }
    
    // MARK: - 分割ビュー
    
    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 18) {
                metaSection.luxCard()
                
                CategorySelector(selectedCategoryId: $selectedCategoryId)
                    .environmentObject(store)
                
                Spacer(minLength: 60) // 電卓に重ならないよう余白
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
            }
        }
    }
    
    private var bgGradient: LinearGradient {
        let colors: [Color] = (scheme == .dark)
        ? [Color.black, Color(white: 0.15)]
        : [Color(white: 0.98), Color(white: 0.94)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    private var keypadBar: some View {
        // ここもネストを避けて型を軽く
        let barBackground: AnyView = {
            if scheme == .dark {
                return AnyView(Color(white: 0.08).opacity(0.95))
            } else {
                return AnyView(Rectangle().fill(.regularMaterial))
            }
        }()
        
        return NumericKeypad(amount: $amount, maxDigits: 9)
            .tint(type == .income ? .green : .accentColor)
            .padding(.top, 8)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(barBackground)
            .overlay(Divider(), alignment: .top)
            .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("保存") { save() }
                .disabled(store.categories.isEmpty || amount == 0 || selectedCategoryId == nil)
        }
    }
    
    // MARK: - Actions
    
    private func save() {
        guard
            let selId = selectedCategoryId,
            let chosen = store.categories.first(where: { $0.id == selId }),
            amount > 0
        else { return }
        
        let tx = Transaction(
            date: date,
            amount: amount,
            type: type,
            memo: memo,
            categoryId: chosen.id
        )
        store.addTransaction(tx)
        dismiss()
    }
}
