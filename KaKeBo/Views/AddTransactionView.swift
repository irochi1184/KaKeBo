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
    
    @State private var date: Date = Date()
    @State private var amount: Int = 0
    @State private var type: TransactionType = .expense
    @State private var memo: String = ""
    
    @State private var selectedCategoryId: UUID?
    
    init(defaultCategoryId: UUID? = nil) {
        _selectedCategoryId = State(initialValue: defaultCategoryId)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    
                    // セクション1：取引メタ（種別/日付/メモ）
                    VStack(alignment: .leading, spacing: 14) {
                        Text("詳細").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        
                        Picker("", selection: $type) {
                            ForEach(TransactionType.allCases, id: \.self) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        DatePicker("日付", selection: $date, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "ja_JP")) // ← 個別指定でもOK
                            .datePickerStyle(.compact)
                        
                        TextField("メモ（任意）", text: $memo)
                            .textFieldStyle(.roundedBorder)
                    }
                    .luxCard()
                    
                    // セクション2：カテゴリ（カードセレクタ）
                    CategorySelector(selectedCategoryId: $selectedCategoryId)
                        .environmentObject(store)
                    
                    // セクション3：金額テンキー（カード化）
                    VStack(alignment: .leading, spacing: 12) {
                        Text("金額").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        NumericKeypad(amount: $amount, maxDigits: 9)
                            .tint(type == .income ? .green : .accentColor)
                    }
                    .luxCard()
                    
                    Spacer(minLength: 8)
                }
                .padding(.top, 12)
                .padding(.horizontal)
            }
            .background(
                LinearGradient(
                    colors: [Color(white: 0.98), Color(white: 0.94)],
                    startPoint: .top, endPoint: .bottom
                ).ignoresSafeArea()
            )
            .navigationTitle("新規追加")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
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
                    .disabled(store.categories.isEmpty || amount == 0 || selectedCategoryId == nil)
                }
            }
        }
    }
}
