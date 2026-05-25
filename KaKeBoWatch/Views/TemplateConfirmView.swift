//
//  TemplateConfirmView.swift
//  KaKeBoWatch
//
//  テンプレート選択後の確認・記録画面
//

import SwiftUI

struct TemplateConfirmView: View {
    @EnvironmentObject var session: WatchSessionManager
    @Environment(\.dismiss) private var dismiss

    let template: WatchTemplate
    @State private var showSuccess = false
    @State private var showError = false
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 12) {
            // カテゴリアイコン
            Image(systemName: template.categorySymbol)
                .font(.title2)
                .foregroundStyle(Color.fromHex(template.categoryColorHex))

            // テンプレート名
            Text(template.title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // 金額
            Text("¥\(template.amount)")
                .font(.title3.bold())
                .foregroundStyle(template.type == "expense" ? .red : .green)

            // カテゴリ名
            Text(template.categoryName)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            // 記録ボタン
            Button {
                isSending = true
                session.addTransaction(template: template) { success in
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
            .buttonStyle(.borderedProminent)
            .tint(template.type == "expense" ? .red : .green)
            .disabled(showSuccess || isSending)
        }
        .padding()
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
                // エラー表示後2秒で状態リセット（再試行可能に）
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    showError = false
                }
            }
        }
        .navigationTitle("確認")
        .navigationBarTitleDisplayMode(.inline)
    }
}
