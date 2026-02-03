//
//  CloudKitShareAcceptanceQueue.swift
//  KaKeBo
//
//  Created by ChatGPT on 2025/12/30.
//

import Foundation
import CloudKit

/// CloudKit の共有招待リンクから受け取ったメタデータを溜めておき、
/// アプリ側で安全に処理できるタイミングで取り出せるようにするキュー。
final class CloudKitShareAcceptanceQueue {
    static let shared = CloudKitShareAcceptanceQueue()

    private var pending: [CKShare.Metadata] = []
    private let lock = NSLock()

    /// 招待メタデータをキューに積み、通知も同時に飛ばす。
    func enqueue(_ metadata: CKShare.Metadata) {
        lock.lock()
        pending.append(metadata)
        lock.unlock()

        NotificationCenter.default.post(name: .cloudKitShareAccepted, object: metadata)
    }

    /// 溜まっている招待メタデータをすべて取り出す。
    func drain() -> [CKShare.Metadata] {
        lock.lock()
        defer { lock.unlock() }
        let items = pending
        pending.removeAll()
        return items
    }
}
