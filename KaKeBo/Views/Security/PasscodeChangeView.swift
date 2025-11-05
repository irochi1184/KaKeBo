//
//  PasscodeChangeView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import SwiftUI

struct PasscodeChangeView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var lock: AppLockManager
    
    enum Step { case verifyCurrent, enterNew, confirmNew }
    @State private var step: Step = .verifyCurrent
    
    let digits: Int
    let onFinished: () -> Void
    let onCanceled: () -> Void
    
    @State private var currentInput: String = ""
    @State private var firstNew: String = ""
    @State private var working: String = ""
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Spacer(minLength: 16)
                Text(titleText)
                    .font(.headline)
                
                PasscodeDots(length: digits, filled: working.count)
                
                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
                
                PasscodePad(input: $working, digits: digits, onComplete: handleComplete)
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
        case .verifyCurrent: return "現在のパスコードを入力"
        case .enterNew:      return "新しいパスコードを入力"
        case .confirmNew:    return "確認のため、もう一度入力"
        }
    }
    
    private func handleComplete(_ code: String) {
        switch step {
        case .verifyCurrent:
            if lock.unlockWithPassword(code) {
                // 現在の確認は成功だが、ここではロック解除意図ではないのでロック状態は変更しない（lastUnlockAtの更新は問題ない想定）
                currentInput = code
                working = ""
                errorMessage = nil
                step = .enterNew
            } else {
                errorMessage = "現在のパスコードが違います"
                working = ""
            }
            
        case .enterNew:
            firstNew = code
            working = ""
            errorMessage = nil
            step = .confirmNew
            
        case .confirmNew:
            guard code == firstNew else {
                errorMessage = "一致しません。もう一度お試しください。"
                working = ""
                return
            }
            do {
                try lock.setNewPassword(code)
                onFinished()
                dismiss()
            } catch {
                errorMessage = "保存に失敗しました: \(error.localizedDescription)"
                working = ""
            }
        }
    }
    
    private func cancelFlow() {
        onCanceled()
        dismiss()
    }
}
