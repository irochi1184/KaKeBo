//
//  Views/Security/LockSettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import SwiftUI
import LocalAuthentication

struct LockSettingsView: View {
    @EnvironmentObject var lock: AppLockManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var enabled: Bool = false
    @State private var biometricsOn: Bool = false
    @State private var hasPw: Bool = false
    
    // シート制御
    @State private var showLengthSheet = false
    @State private var showSetPw = false
    @State private var showChangePw = false
    @State private var didAppear = false   // 初回同期ガード
    
    // 作成フローで使う桁数
    @State private var lengthToCreate: Int = 6
    
    var body: some View {
        Form {
            Section {
                Toggle("アプリロックを有効にする", isOn: $enabled)
                    .onChange(of: enabled) { oldValue, newValue in
                        guard didAppear else { return } // 初期同期は無視
                        if newValue {
                            if lock.hasPassword() {
                                if !lock.isEnabled { lock.enableAfterSetup() }
                                enabled = true
                            } else {
                                // 未設定 → まず桁数選択
                                enabled = false
                                lengthToCreate = lock.passcodeLength // 既定値（6）か前回値
                                DispatchQueue.main.async { showLengthSheet = true }
                            }
                        } else {
                            // 無効化 → 削除
                            lock.disableAndErase()
                            enabled = false
                            biometricsOn = false
                            hasPw = false
                        }
                    }
                
                if enabled {
                    Toggle("生体認証（Face ID / Touch ID）を使用", isOn: $biometricsOn)
                        .onChange(of: biometricsOn) { _, v in lock.setBiometrics(v) }
                        .disabled(!canUseBiometrics())
                        .opacity(canUseBiometrics() ? 1 : 0.5)
                }
            }
            
            if enabled {
                Section("パスコード") {
                    if hasPw {
                        Button("パスコードを変更") {
                            // 変更は現行の桁数で行う（※必要なら長さ変更フローも追加可）
                            DispatchQueue.main.async { showChangePw = true }
                        }
                    } else {
                        Button("パスコードを作成") {
                            lengthToCreate = lock.passcodeLength
                            DispatchQueue.main.async { showLengthSheet = true }
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("アプリロック")
        .onAppear {
            enabled = lock.isEnabled
            biometricsOn = lock.biometricsEnabled
            hasPw = lock.hasPassword()
            lengthToCreate = lock.passcodeLength
            didAppear = true
        }
        // 1) 桁数選択シート（4〜10）
        .sheet(isPresented: $showLengthSheet) {
            PasscodeLengthPickerView(
                initial: lengthToCreate,
                onCancel: { showLengthSheet = false },
                onSelect: { len in
                    lock.setPasscodeLength(len)
                    lengthToCreate = len
                    showLengthSheet = false
                    // 次のランループでセットアップへ
                    DispatchQueue.main.async { showSetPw = true }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        // 2) 新規設定シート（選んだ桁数で
        .sheet(isPresented: $showSetPw) {
            PasscodeSetupView(
                digits: lengthToCreate,
                onFinished: {
                    // 直後はロックしない
                    lock.enableAfterSetup(unlockNow: true)
                    enabled = true
                    hasPw = true
                },
                onCanceled: {
                    enabled = false
                }
            )
            .environmentObject(lock)
            .presentationDragIndicator(.visible)
        }

        // 3) 変更シート（現行の桁数で）
        .sheet(isPresented: $showChangePw) {
            PasscodeChangeView(
                digits: lock.passcodeLength,
                onFinished: { hasPw = true },
                onCanceled: { }
            )
            .environmentObject(lock)
            .presentationDragIndicator(.visible)
        }
    }
    
    private func canUseBiometrics() -> Bool {
        let ctx = LAContext(); var err: NSError?
        return ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
    }
}
