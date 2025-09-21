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
    @Environment(\.colorScheme) private var colorScheme // ← ダークモード判定用
    
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
                    // 種別・日付・メモ
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
                    .luxCard()
                    
                    // カテゴリ
                    CategorySelector(selectedCategoryId: $selectedCategoryId)
                        .environmentObject(store)
                    
                    Spacer(minLength: 60) // ← 電卓に重ならないよう余白
                }
                .padding(.top, 12)
                .padding(.horizontal)
            }
            .background(
                LinearGradient(
                    colors: colorScheme == .dark
                    ? [Color.black, Color(white: 0.15)]
                    : [Color(white: 0.98), Color(white: 0.94)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("新規追加")
            .navigationBarTitleDisplayMode(.inline)
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
            .safeAreaInset(edge: .bottom) {
                NumericKeypad(amount: $amount, maxDigits: 9)
                    .tint(type == .income ? .green : .accentColor)
                    .padding(.top, 8)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .background(
                        ZStack {
                            if colorScheme == .dark {
                                Color(white: 0.08).opacity(0.95)
                            } else {
                                Rectangle().fill(.regularMaterial)
                            }
                        }
                    )
                    .overlay(Divider(), alignment: .top)
                    .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
            }
        }
    }
}
