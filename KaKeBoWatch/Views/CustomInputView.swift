//
//  CustomInputView.swift
//  KaKeBoWatch
//
//  カスタム金額入力画面
//

import SwiftUI

struct CustomInputView: View {
    @EnvironmentObject var session: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var isExpense = true
    @State private var selectedCategoryId: UUID?
    @State private var memo = ""
    @State private var showSuccess = false
    @State private var showError = false
    @State private var isSending = false

    private var amount: Int {
        Int(amountText) ?? 0
    }

    var body: some View {
        List {
            // 収入/支出切替
            Section {
                Picker("種別", selection: $isExpense) {
                    Text("支出").tag(true)
                    Text("収入").tag(false)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            // 金額入力
            Section("金額") {
                TextField("0", text: $amountText)
                    #if os(watchOS)
                    .textContentType(.oneTimeCode) // 数字キーボードを出すためのワークアラウンド
                    #endif
            }

            // カテゴリ選択
            Section("カテゴリ") {
                if session.categories.isEmpty {
                    Text("同期待ち...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(session.categories.prefix(8)) { cat in
                        Button {
                            selectedCategoryId = cat.id
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.symbolName)
                                    .font(.caption2)
                                    .foregroundStyle(Color.fromHex(cat.colorHex))
                                Text(cat.name)
                                    .font(.caption)
                                Spacer()
                                if selectedCategoryId == cat.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // メモ
            Section("メモ") {
                TextField("任意", text: $memo)
            }

            // 記録ボタン
            Section {
                Button {
                    guard amount > 0, let catId = selectedCategoryId else { return }
                    isSending = true
                    session.addCustomTransaction(
                        amount: amount,
                        type: isExpense ? "expense" : "income",
                        categoryId: catId,
                        memo: memo
                    ) { success in
                        isSending = false
                        if success {
                            showSuccess = true
                        } else {
                            showError = true
                        }
                    }
                } label: {
                    if isSending {
                        ProgressView()
                    } else {
                        Label("記録する", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(amount == 0 || selectedCategoryId == nil || showSuccess || isSending)
                .listRowBackground(
                    (amount > 0 && selectedCategoryId != nil)
                    ? (isExpense ? Color.red.opacity(0.3) : Color.green.opacity(0.3))
                    : Color.gray.opacity(0.2)
                )
            }
        }
        .overlay {
            if showSuccess {
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.green)
                    Text("記録しました")
                        .font(.caption)
                }
                .transition(.scale.combined(with: .opacity))
            } else if showError {
                VStack {
                    Image(systemName: "xmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text("送信失敗")
                        .font(.caption)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: showSuccess)
        .animation(.easeInOut, value: showError)
        .onChange(of: showSuccess) { _, success in
            if success {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    dismiss()
                }
            }
        }
        .onChange(of: showError) { _, error in
            if error {
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    showError = false
                }
            }
        }
        .navigationTitle("入力")
    }
}
