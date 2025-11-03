//
//  Views/Security/LockScreenView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import SwiftUI

struct LockScreenView: View {
    @EnvironmentObject var lock: AppLockManager
    @Environment(\.colorScheme) private var scheme
    
    @State private var code: String = ""
    @State private var errorMessage: String?
    @State private var tryingBio = false
    
    // 桁数は必要に応じて 4/6 を選択
    private var passcodeDigits: Int { max(4, min(10, lock.passcodeLength)) }
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 24)
            
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(.primary)
            
            Text("パスコードを入力")
                .font(.headline)
            
            PasscodeDots(length: passcodeDigits, filled: code.count)
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote).foregroundStyle(.red)
            }
            
            PasscodePad(
                input: $code,
                digits: passcodeDigits,
                onComplete: { entered in
                    if lock.unlockWithPassword(entered) {
                        errorMessage = nil
                        code = ""
                    } else {
                        // 失敗時は軽くバイブ等も検討可
                        errorMessage = "パスコードが違います"
                        code = ""
                    }
                },
                showBiometrics: lock.biometricsEnabled,
                onBiometrics: {
                    Task {
                        tryingBio = true
                        let ok = await lock.tryBiometricsUnlock()
                        tryingBio = false
                        if !ok {
                            errorMessage = "生体認証に失敗しました"
                        }
                    }
                }
            )
            .padding(.top, 6)
            
            Spacer()
        }
        .padding(.bottom, 24)
        .interactiveDismissDisabled(true)
    }
}
