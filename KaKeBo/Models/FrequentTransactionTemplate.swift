import Foundation

/// よく使う取引を素早く呼び出すためのテンプレート
struct FrequentTransactionTemplate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var amount: Int
    var type: TransactionType
    var memo: String
    var categoryId: UUID
    var tags: [String]

    func isEquivalent(to other: FrequentTransactionTemplate) -> Bool {
        return amount == other.amount
        && type == other.type
        && memo == other.memo
        && categoryId == other.categoryId
        && tags == other.tags
    }
}
