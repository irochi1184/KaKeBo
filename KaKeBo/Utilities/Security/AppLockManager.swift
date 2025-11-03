//
//  Utilities/Security/AppLockManager.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import Foundation
import LocalAuthentication
import Combine

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()
    
    // 公開状態
    @Published var isEnabled: Bool
    @Published var biometricsEnabled: Bool
    @Published var isLocked: Bool
    @Published var passcodeLength: Int
    
    // 内部保持
    private let service = "com.irochi.KaKeBo.lock"
    private let accHash = "passwordHash"
    private let accSalt = "passwordSalt"
    
    private init() {
        let d = UserDefaults.standard
        let enabled = d.bool(forKey: "applock.enabled")
        let bio = d.bool(forKey: "applock.biometrics")
        let locked = enabled // 起動直後は有効ならロック
        let length = Self.clampLength(d.integer(forKey: "applock.passcodeLength"), defaultValue: 6)
        
        _isEnabled = Published(initialValue: enabled)
        _biometricsEnabled = Published(initialValue: bio)
        _isLocked = Published(initialValue: locked)
        _passcodeLength = Published(initialValue: length)
    }
    
    private func persist() {
        let d = UserDefaults.standard
        d.set(isEnabled, forKey: "applock.enabled")
        d.set(biometricsEnabled, forKey: "applock.biometrics")
        d.set(passcodeLength, forKey: "applock.passcodeLength")
    }
    
    // 設定変更API
    func setEnabled(_ on: Bool) {
        if on {
            guard hasPassword() else {
                isEnabled = false
                isLocked = false
                persist()
                return
            }
            isEnabled = true
            isLocked = true
        } else {
            disableAndErase()
        }
        persist()
    }
    
    /// 設定フロー完了後に正式有効化
    func enableAfterSetup(unlockNow: Bool = true) {
        isEnabled = true
        if unlockNow {
            // 直後は本人確認済みなのでロックしない
            isLocked = false
        } else {
            isLocked = true
        }
        persist()
    }
    
    func setBiometrics(_ on: Bool) { biometricsEnabled = on; persist() }
    
    /// ★ 追加：桁数の保存（4〜10にクランプ）
    func setPasscodeLength(_ n: Int) {
        passcodeLength = Self.clampLength(n, defaultValue: 6)
        persist()
    }
    
    private static func clampLength(_ n: Int, defaultValue: Int) -> Int {
        let val = (4...10).contains(n) ? n : defaultValue
        return max(4, min(10, val))
    }
    
    // --- パスワード設定／検証 ---
    func hasPassword() -> Bool {
        SecureKeychain.get(account: accHash, service: service) != nil
    }
    
    func setNewPassword(_ password: String) throws {
        let salt = CryptoHelpers.randomBytes(16)
        let hash = CryptoHelpers.sha256(salt + password.data(using: .utf8)!)
        try SecureKeychain.set(salt, account: accSalt, service: service)
        try SecureKeychain.set(hash, account: accHash, service: service)
    }
    
    func verifyPassword(_ password: String) -> Bool {
        guard
            let salt = SecureKeychain.get(account: accSalt, service: service),
            let stored = SecureKeychain.get(account: accHash, service: service)
        else { return false }
        let hash = CryptoHelpers.sha256(salt + password.data(using: .utf8)!)
        return hash == stored
    }
    
    // --- ロック／アンロック ---
    func lockOnActivateIfEnabled() {
        isLocked = isEnabled
    }
    
    func unlockWithPassword(_ password: String) -> Bool {
        guard verifyPassword(password) else { return false }
        isLocked = false
        return true
    }
    
    func tryBiometricsUnlock() async -> Bool {
        guard isEnabled, biometricsEnabled else { return false }
        let ctx = LAContext()
        var err: NSError?
        if ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) {
            do {
                let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "KaKeBoのロック解除")
                if ok {
                    isLocked = false
                    return true
                }
            } catch { /* ignore */ }
        }
        return false
    }
    
    // --- 無効化時の完全消去 ---
    func disableAndErase() {
        isEnabled = false
        isLocked = false
        biometricsEnabled = false
        erasePassword()
        persist()
    }
    
    private func erasePassword() {
        SecureKeychain.delete(account: accHash, service: service)
        SecureKeychain.delete(account: accSalt, service: service)
    }
}

// Data + Data
fileprivate func + (lhs: Data, rhs: Data) -> Data {
    var d = Data(lhs); d.append(rhs); return d
}
