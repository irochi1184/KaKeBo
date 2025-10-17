import Foundation
import SwiftUI
import Combine
import WidgetKit

final class DataStore: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var budgets: [Budget] = []

    private let categoriesURL: URL
    private let transactionsURL: URL
    private let budgetsURL: URL

    init() {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else {
#if DEBUG
            print("❌ AppGroup URL 取得に失敗: \(AppGroup.id)。entitlements/Team/BundleID を確認して下さい。")
#endif
            // フォールバック：ドキュメント配下（初期起動用・暫定）
            let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            categoriesURL   = doc.appendingPathComponent("categories.json")
            transactionsURL = doc.appendingPathComponent("transactions.json")
            budgetsURL      = doc.appendingPathComponent("budgets.json")
            load()
            if categories.isEmpty { seed() }
            return
        }
        
        categoriesURL   = base.appendingPathComponent("categories.json")
        transactionsURL = base.appendingPathComponent("transactions.json")
        budgetsURL      = base.appendingPathComponent("budgets.json")
        
        // 旧ドキュメントからの一度きりの移行（既存ユーザー救済）
        migrateFromDocumentsIfNeeded(to: base)
        
        load()
        if categories.isEmpty { seed() }
    }

    private func migrateFromDocumentsIfNeeded(to appGroupBase: URL) {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let old = [
            ("categories.json", categoriesURL),
            ("transactions.json", transactionsURL),
            ("budgets.json", budgetsURL)
        ]
        for (name, dest) in old {
            let src = doc.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: src.path),
               !FileManager.default.fileExists(atPath: dest.path) {
                do {
                    try FileManager.default.copyItem(at: src, to: dest)
#if DEBUG
                    print("Migrated \(name) to AppGroup container.")
#endif
                } catch { print("Migration error(\(name)):", error) }
            }
        }
    }

    private func seed() {
        categories = [
            Category(name: "食費", symbolName: "cart", color: .green),
            Category(name: "交通", symbolName: "tram.fill", color: .blue),
            Category(name: "娯楽", symbolName: "gamecontroller.fill", color: .purple),
            Category(name: "収入", symbolName: "banknote", color: .orange),
        ]
        save()
    }

    // MARK: - CRUD
    func addTransaction(_ tx: Transaction) {
        transactions.insert(tx, at: 0)
        saveTransactions()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func deleteTransactions(at offsets: IndexSet) {
        transactions.remove(atOffsets: offsets)
        saveTransactions()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func addCategory(_ cat: Category) {
        categories.append(cat)
        saveCategories()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateCategory(_ cat: Category) {
        if let idx = categories.firstIndex(where: { $0.id == cat.id }) {
            categories[idx] = cat
            saveCategories()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func deleteCategory(_ cat: Category) {
        categories.removeAll(where: { $0.id == cat.id })
        transactions.removeAll(where: { $0.categoryId == cat.id })
        save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Persistence
    private func load() {
        categories = loadJSON([Category].self, from: categoriesURL) ?? []
        if let dtos = loadJSON([TransactionDTO].self, from: transactionsURL) {
            transactions = dtos.map { dto in
                let typeVal: TransactionType = (dto.type.lowercased() == "income") ? .income : .expense
                return Transaction(id: dto.id, date: dto.date, amount: dto.amount, type: typeVal, memo: dto.memo, categoryId: dto.categoryId)
            }
        } else if let old = loadJSON([Transaction].self, from: transactionsURL) {
            transactions = old
        } else {
            transactions = []
        }
        budgets = loadJSON([Budget].self, from: budgetsURL) ?? []
    }

    public func save() {
        saveJSON(categories, to: categoriesURL)
        
        let dtos: [TransactionDTO] = transactions.map { tx in
            let typeStr: String
            switch tx.type { case .income: typeStr = "income"; case .expense: typeStr = "expense" }
            return TransactionDTO(id: tx.id, date: tx.date, amount: tx.amount, type: typeStr, categoryId: tx.categoryId, memo: tx.memo)
        }
        saveJSON(dtos, to: transactionsURL)
        
        saveJSON(budgets, to: budgetsURL)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func saveCategories() {
        saveJSON(categories, to: categoriesURL)
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func saveTransactions() {
        let dtos: [TransactionDTO] = transactions.map { tx in
            let typeStr: String
            switch tx.type { case .income: typeStr = "income"; case .expense: typeStr = "expense" }
            return TransactionDTO(id: tx.id, date: tx.date, amount: tx.amount, type: typeStr, categoryId: tx.categoryId, memo: tx.memo)
        }
        saveJSON(dtos, to: transactionsURL)
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func saveBudgets() {
        saveJSON(budgets, to: budgetsURL)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Try ISO8601 first
        let dec1 = JSONDecoder()
        dec1.dateDecodingStrategy = .iso8601
        if let val = try? dec1.decode(T.self, from: data) { return val }
        // Fallback to default decoding
        let dec2 = JSONDecoder()
        if let val = try? dec2.decode(T.self, from: data) { return val }
#if DEBUG
        print("⚠️ loadJSON decode failed for: \(url.lastPathComponent)")
#endif
        return nil
    }

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let data = try enc.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Save error (\(url.lastPathComponent)):", error)
        }
    }
}

extension DataStore {
    func upsertTransaction(_ tx: Transaction) {
        if let i = transactions.firstIndex(where: { $0.id == tx.id }) {
            transactions[i] = tx
        } else {
            transactions.insert(tx, at: 0)
        }
        saveTransactions()
    }
    
    /// ID配列でまとめて削除して保存
    func deleteTransactions(with ids: [UUID]) {
        guard !ids.isEmpty else { return }
        transactions.removeAll { ids.contains($0.id) }
        saveTransactions()
    }
    
    func deleteTransaction(id: UUID) {
        deleteTransactions(with: [id])
    }
    
    func updateTransaction(_ tx: Transaction) {
        // 既存更新だけに限定したい場合はこちらを使ってもOK
        guard let idx = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        transactions[idx] = tx
        saveTransactions()
    }
}
