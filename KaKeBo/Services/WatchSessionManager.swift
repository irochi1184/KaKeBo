//
//  Services/WatchSessionManager.swift
//  KaKeBo
//
//  iPhone側 WatchConnectivity 管理
//  Watch からのデータ要求・取引追加を処理
//

import Foundation
import WatchConnectivity

final class PhoneSessionManager: NSObject {
    static let shared = PhoneSessionManager()

    private weak var dataStore: DataStore?

    private override init() {
        super.init()
    }

    /// DataStoreを登録して WCSession を有効化
    func configure(with store: DataStore) {
        self.dataStore = store
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    /// データ変更時に Watch へプッシュ
    func pushUpdate() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isPaired,
              WCSession.default.isWatchAppInstalled else { return }

        let context = buildSyncPayload()
        try? WCSession.default.updateApplicationContext(context)
    }

    // MARK: - Private

    private func buildSyncPayload() -> [String: Any] {
        guard let store = dataStore else { return [:] }

        // よく使うテンプレートを Watch 用に変換
        let watchTemplates: [WatchTemplateDTO] = store.frequentTemplates.prefix(10).map { tpl in
            let cat = store.categories.first(where: { $0.id == tpl.categoryId })
            return WatchTemplateDTO(
                id: tpl.id,
                title: tpl.title,
                amount: tpl.amount,
                type: tpl.type.rawValue == "支出" ? "expense" : "income",
                memo: tpl.memo,
                categoryId: tpl.categoryId,
                categoryName: cat?.name ?? "未分類",
                categorySymbol: cat?.symbolName ?? "tag.fill",
                categoryColorHex: cat?.colorHex ?? "#007AFF",
                tags: tpl.tags
            )
        }

        // カテゴリ一覧
        let watchCategories: [WatchCategoryDTO] = store.categories.map { cat in
            WatchCategoryDTO(id: cat.id, name: cat.name, symbolName: cat.symbolName, colorHex: cat.colorHex)
        }

        // 今日の支出
        let today = Calendar.current.startOfDay(for: Date())
        let todayExpense = store.transactions
            .filter { $0.type == .expense && Calendar.current.isDate($0.date, inSameDayAs: today) }
            .reduce(0) { $0 + $1.amount }

        // 今月の収支
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        let monthStart = cal.date(from: comps) ?? today
        let monthTransactions = store.transactions.filter { $0.date >= monthStart }
        let monthExpense = monthTransactions.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let monthIncome = monthTransactions.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }

        var payload: [String: Any] = [
            "todayExpense": todayExpense,
            "monthExpense": monthExpense,
            "monthIncome": monthIncome
        ]

        if let templatesData = try? JSONEncoder().encode(watchTemplates) {
            payload["templates"] = templatesData
        }
        if let categoriesData = try? JSONEncoder().encode(watchCategories) {
            payload["categories"] = categoriesData
        }

        return payload
    }

    private func handleAddTransaction(_ message: [String: Any]) {
        guard let store = dataStore,
              let amount = message["amount"] as? Int,
              let typeStr = message["type"] as? String,
              let categoryIdStr = message["categoryId"] as? String,
              let categoryId = UUID(uuidString: categoryIdStr) else { return }

        let memo = message["memo"] as? String ?? ""
        let tags = message["tags"] as? [String] ?? []
        let type: TransactionType = typeStr == "income" ? .income : .expense

        let transaction = Transaction(
            date: Date(),
            amount: amount,
            type: type,
            memo: memo,
            categoryId: categoryId,
            tags: tags
        )

        // メインスレッドから呼ばれる前提（session delegate 経由）
        store.addTransaction(transaction)
    }
}

// MARK: - WCSessionDelegate

extension PhoneSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            DispatchQueue.main.async {
                self.pushUpdate()
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // 再アクティベート
        WCSession.default.activate()
    }

    // Watch からのメッセージ受信（デリゲートスレッドで呼ばれる）
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let action = message["action"] as? String ?? ""

        // DataStore はメインスレッドでのみアクセス
        DispatchQueue.main.async { [weak self] in
            guard let self else { replyHandler([:]); return }

            switch action {
            case "sync":
                replyHandler(self.buildSyncPayload())

            case "addTransaction":
                self.handleAddTransaction(message)
                // addTransaction → save() → 同期的に完了するのでそのまま返す
                replyHandler(self.buildSyncPayload())

            default:
                replyHandler(self.buildSyncPayload())
            }
        }
    }
}

// MARK: - Watch 通信用 DTO

private struct WatchTemplateDTO: Codable {
    let id: UUID
    let title: String
    let amount: Int
    let type: String
    let memo: String
    let categoryId: UUID
    let categoryName: String
    let categorySymbol: String
    let categoryColorHex: String
    let tags: [String]
}

private struct WatchCategoryDTO: Codable {
    let id: UUID
    let name: String
    let symbolName: String
    let colorHex: String
}
