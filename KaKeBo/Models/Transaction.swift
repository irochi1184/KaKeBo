import Foundation

enum TransactionType: String, Codable, CaseIterable {
    case expense = "支出"
    case income = "収入"
}

struct Transaction: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var amount: Int
    var type: TransactionType
    var memo: String
    var categoryId: UUID
    var tags: [String]
}
