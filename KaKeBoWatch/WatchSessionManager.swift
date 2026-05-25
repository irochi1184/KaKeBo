//
//  WatchSessionManager.swift
//  KaKeBoWatch
//
//  WatchConnectivity によるiPhoneとのデータ同期管理
//

import Foundation
import WatchConnectivity

final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    // iPhone から受信したデータ
    @Published var templates: [WatchTemplate] = []
    @Published var categories: [WatchCategory] = []
    @Published var todayExpense: Int = 0
    @Published var monthExpense: Int = 0
    @Published var monthIncome: Int = 0

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    /// 通信エラー（UIに表示可能）
    @Published var lastError: String?

    /// iPhone にデータ要求を送信
    func requestSync() {
        guard WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["action": "sync"], replyHandler: { [weak self] reply in
            self?.handleSyncReply(reply)
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async { self?.lastError = error.localizedDescription }
        })
    }

    /// iPhone に取引追加を要求
    func addTransaction(template: WatchTemplate, completion: ((Bool) -> Void)? = nil) {
        let payload: [String: Any] = [
            "action": "addTransaction",
            "amount": template.amount,
            "type": template.type,
            "memo": template.memo,
            "categoryId": template.categoryId.uuidString,
            "tags": template.tags
        ]
        WCSession.default.sendMessage(payload, replyHandler: { [weak self] reply in
            self?.handleSyncReply(reply)
            DispatchQueue.main.async { completion?(true) }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.lastError = error.localizedDescription
                completion?(false)
            }
        })
    }

    /// カスタム金額で取引追加
    func addCustomTransaction(amount: Int, type: String, categoryId: UUID, memo: String, completion: ((Bool) -> Void)? = nil) {
        let payload: [String: Any] = [
            "action": "addTransaction",
            "amount": amount,
            "type": type,
            "memo": memo,
            "categoryId": categoryId.uuidString,
            "tags": [String]()
        ]
        WCSession.default.sendMessage(payload, replyHandler: { [weak self] reply in
            self?.handleSyncReply(reply)
            DispatchQueue.main.async { completion?(true) }
        }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.lastError = error.localizedDescription
                completion?(false)
            }
        })
    }

    private func handleSyncReply(_ reply: [String: Any]) {
        DispatchQueue.main.async {
            if let templatesData = reply["templates"] as? Data,
               let decoded = try? JSONDecoder().decode([WatchTemplate].self, from: templatesData) {
                self.templates = decoded
            }
            if let categoriesData = reply["categories"] as? Data,
               let decoded = try? JSONDecoder().decode([WatchCategory].self, from: categoriesData) {
                self.categories = decoded
            }
            if let today = reply["todayExpense"] as? Int {
                self.todayExpense = today
            }
            if let monthExp = reply["monthExpense"] as? Int {
                self.monthExpense = monthExp
            }
            if let monthInc = reply["monthIncome"] as? Int {
                self.monthIncome = monthInc
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            DispatchQueue.main.async {
                self.requestSync()
            }
        }
    }

    // iPhone からのアプリケーションコンテキスト受信
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        handleSyncReply(applicationContext)
    }

    // iPhone からのメッセージ受信（リアルタイム更新）
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleSyncReply(message)
    }
}
