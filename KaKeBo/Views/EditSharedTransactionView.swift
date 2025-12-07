//
//  Views/EditSharedTransactionView.swift
//  KaKeBo
//
//  Created by OpenAI ChatGPT.
//

import SwiftUI
import CloudKit

struct EditSharedTransactionView: View {
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @Environment(\.dismiss) private var dismiss

    let ledger: SharedLedger
    let transaction: SharedTransaction

    @State private var amount: Int
    @State private var date: Date
    @State private var type: SharedTransactionType
    @State private var memo: String
    @State private var selectedCategoryId: CKRecord.ID?

    init(ledger: SharedLedger, transaction: SharedTransaction) {
        self.ledger = ledger
        self.transaction = transaction

        _amount = State(initialValue: transaction.amount)
        _date = State(initialValue: transaction.date)
        _type = State(initialValue: transaction.type)
        _memo = State(initialValue: transaction.memo ?? "")
        _selectedCategoryId = State(initialValue: transaction.categoryId)
    }

    private var categories: [SharedCategory] {
        sharedLedgerStore.categoriesByLedger[ledger.id] ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("金額") {
                    TextField(
                        "金額",
                        value: $amount,
                        format: .number
                    )
                    .keyboardType(.numberPad)
                }

                Section("種別") {
                    Picker("種別", selection: $type) {
                        Text("支出").tag(SharedTransactionType.expense)
                        Text("収入").tag(SharedTransactionType.income)
                    }
                    .pickerStyle(.segmented)
                }

                Section("カテゴリ") {
                    Picker("カテゴリ", selection: $selectedCategoryId) {
                        ForEach(categories) { cat in
                            HStack {
                                Circle()
                                    .fill(Color.fromHex(cat.colorHex) ?? .gray)
                                    .frame(width: 10, height: 10)
                                Text(cat.name)
                            }
                            .tag(Optional.some(cat.id))
                        }
                    }
                }

                Section("日付") {
                    DatePicker("日付", selection: $date, displayedComponents: .date)
                }

                Section("メモ") {
                    TextField("メモ", text: $memo, axis: .vertical)
                }
            }
            .navigationTitle("共有取引を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(amount <= 0)
                }
            }
        }
    }

    private func save() {
        guard amount > 0 else { return }

        let memoText = memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = categories.first { $0.id == selectedCategoryId }

        Task {
            await sharedLedgerStore.updateTransaction(
                transaction,
                in: ledger,
                amount: amount,
                date: date,
                type: type,
                memo: memoText.isEmpty ? nil : memoText,
                category: category
            )
            dismiss()
        }
    }
}

