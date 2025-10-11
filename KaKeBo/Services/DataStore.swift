import Foundation
import SwiftUI
import Combine

final class DataStore: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var budgets: [Budget] = []

    private let categoriesURL: URL
    private let transactionsURL: URL
    private let budgetsURL: URL

    init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        categoriesURL = base.appendingPathComponent("categories.json")
        transactionsURL = base.appendingPathComponent("transactions.json")
        budgetsURL = base.appendingPathComponent("budgets.json")

        load()
        if categories.isEmpty {
            seed()
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
    }

    func deleteTransactions(at offsets: IndexSet) {
        transactions.remove(atOffsets: offsets)
        saveTransactions()
    }

    func addCategory(_ cat: Category) {
        categories.append(cat)
        saveCategories()
    }

    func updateCategory(_ cat: Category) {
        if let idx = categories.firstIndex(where: { $0.id == cat.id }) {
            categories[idx] = cat
            saveCategories()
        }
    }

    func deleteCategory(_ cat: Category) {
        categories.removeAll(where: { $0.id == cat.id })
        transactions.removeAll(where: { $0.categoryId == cat.id })
        save()
    }

    // MARK: - Persistence
    private func load() {
        categories = loadJSON([Category].self, from: categoriesURL) ?? []
        transactions = loadJSON([Transaction].self, from: transactionsURL) ?? []
        budgets = loadJSON([Budget].self, from: budgetsURL) ?? []
    }

    public func save() {
        saveJSON(categories, to: categoriesURL)
        saveJSON(transactions, to: transactionsURL)
        saveJSON(budgets, to: budgetsURL)
    }

    private func saveCategories() { saveJSON(categories, to: categoriesURL) }
    private func saveTransactions() { saveJSON(transactions, to: transactionsURL) }
    private func saveBudgets() { saveJSON(budgets, to: budgetsURL) }

    private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Save error:", error)
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
