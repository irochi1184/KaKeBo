//
//  Models/LedgerContext.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/27.
//

import Foundation
import CloudKit
import Combine

final class LedgerContext: ObservableObject {
    enum Mode {
        case personal
        case shared
    }
    
    @Published var mode: Mode = .personal
    @Published var selectedSharedLedgerId: CKRecord.ID? = nil
    
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
}
