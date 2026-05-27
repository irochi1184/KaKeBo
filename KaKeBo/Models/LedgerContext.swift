//
//  Models/LedgerContext.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/27.
//

import Foundation
import CloudKit
import Combine

@MainActor
final class LedgerContext: ObservableObject {
    
    // MARK: - Mode
    
    enum Mode: String {
        case personal
        case shared
    }
    
    // MARK: - Published
    
    @Published var mode: Mode = .personal
    @Published var selectedSharedLedgerId: CKRecord.ID? = nil
    
    /// 起動直後の復元が完了したか
    @Published var isRestored: Bool = false
    
    // MARK: - Computed
    
    var isPersonal: Bool { mode == .personal }
    var isShared: Bool { mode == .shared }
    
    /// 現在選択中の共有レジャーを取り出すヘルパ
    func currentSharedLedger(from store: SharedLedgerStore) -> SharedLedger? {
        if let id = selectedSharedLedgerId {
            return store.ledgers.first(where: { $0.id == id })
        } else {
            return store.ledgers.first
        }
    }
    
    // MARK: - UserDefaults
    
    private let defaults = UserDefaults.appGroup
    private let modeKey = "ledger.lastMode"
    private let sharedIdKey = "ledger.lastSharedLedgerId"
    
    // MARK: - Init
    
    init() {
        defaults.migrateIfNeeded(keys: [modeKey, sharedIdKey])
        // 起動直後はこちらで「即座に」モードだけ復元する
        if let raw = defaults.string(forKey: modeKey),
           let m = Mode(rawValue: raw) {
            self.mode = m
        } else {
            self.mode = .personal
        }
    }
    
    // MARK: - Public actions
    
    func setPersonal() {
        mode = .personal
        selectedSharedLedgerId = nil
        persist()
    }
    
    func setShared(id: CKRecord.ID) {
        mode = .shared
        selectedSharedLedgerId = id
        persist()
    }
    
    // MARK: - Restore on launch
    
    /// 起動時に「一度だけ」呼ぶ
    func restoreIfNeeded(sharedLedgerStore: SharedLedgerStore) async {
        guard !isRestored else { return }

        // 1. 共有家計簿一覧を取得（失敗しても起動を止めない）
        let reloadSuccess = await sharedLedgerStore.reloadLedgers()

        #if DEBUG
        print("ℹ️ [LedgerContext] reloadLedgers 結果: \(reloadSuccess ? "成功" : "失敗") ledgers=\(sharedLedgerStore.ledgers.count)件")
        #endif

        // 2. 前回選択していた shared ledger ID を復元
        if let data = defaults.data(forKey: sharedIdKey),
           let id = try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: CKRecord.ID.self,
            from: data
           ) {
            selectedSharedLedgerId = id
        }

        // 3. shared モード時の整合性チェック
        if mode == .shared {
            if !reloadSuccess {
                // CloudKit 失敗時は個人モードにフォールバック
                #if DEBUG
                print("⚠️ [LedgerContext] CloudKit 読み込み失敗 → 個人モードにフォールバック")
                #endif
                mode = .personal
                selectedSharedLedgerId = nil
                persist()
            } else if let id = selectedSharedLedgerId,
               sharedLedgerStore.ledgers.contains(where: { $0.id == id }) {
                // OK（そのまま）
            } else if let first = sharedLedgerStore.ledgers.first {
                // 前回の ledger が消えていた → 先頭にフォールバック
                selectedSharedLedgerId = first.id
                persist()
            } else {
                // 共有 ledger が1件も無い
                mode = .personal
                selectedSharedLedgerId = nil
                persist()
            }
        }

        // この瞬間に HomeView が切り替わる
        isRestored = true
    }

    /// タイムアウト時に強制的に個人モードで復元完了にする
    func forceRestoreAsPersonal() {
        guard !isRestored else { return }
        #if DEBUG
        print("⚠️ [LedgerContext] forceRestoreAsPersonal 呼び出し")
        #endif
        mode = .personal
        selectedSharedLedgerId = nil
        persist()
        isRestored = true
    }
    
    // MARK: - Persist
    
    private func persist() {
        defaults.set(mode.rawValue, forKey: modeKey)
        
        if let id = selectedSharedLedgerId,
           let data = try? NSKeyedArchiver.archivedData(
            withRootObject: id,
            requiringSecureCoding: true
           ) {
            defaults.set(data, forKey: sharedIdKey)
        } else {
            defaults.removeObject(forKey: sharedIdKey)
        }
    }
}
