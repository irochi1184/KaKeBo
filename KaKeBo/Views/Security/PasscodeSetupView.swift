//
//  Views/Security/PasscodeSetupView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import SwiftUI

struct PasscodeSetupView: View {
    enum Step { case enter, confirm }
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var lock: AppLockManager
    
    @State private var step: Step = .enter
    @State private var first: String = ""
    @State private var current: String = ""
    @State private var errorMessage: String?
    
    let digits: Int
    /// 完了時に呼ばれる（Settings 側で enableAfterSetup() を呼び出す）
    let onFinished: () -> Void
    /// キャンセル時
    let onCanceled: () -> Void
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 16)
                Text(titleText)
                    .font(.headline)
                
                PasscodeDots(length: digits, filled: current.count)
                
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                
                PasscodePad(input: $current, digits: digits, onComplete: handleComplete)
                    .padding(.top, 6)
                
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { cancelFlow() }
                }
            }
        }
    }
    
    private var titleText: String {
        switch step {
        case .enter: return "新しいパスコードを入力"
        case .confirm: return "確認のため、もう一度入力"
        }
    }
    
    private func handleComplete(_ code: String) {
        switch step {
        case .enter:
            first = code
            current = ""
            errorMessage = nil
            step = .confirm
        case .confirm:
            guard code == first else {
                errorMessage = "一致しません。もう一度お試しください。"
                current = ""
                // 戻さず同じステップで再入力
                return
            }
            do {
                try lock.setNewPassword(code)
                onFinished()
                dismiss()
            } catch {
                errorMessage = "保存に失敗しました: \(error.localizedDescription)"
                current = ""
            }
        }
    }
    
    private func cancelFlow() {
        onCanceled()
        dismiss()
    }
}
