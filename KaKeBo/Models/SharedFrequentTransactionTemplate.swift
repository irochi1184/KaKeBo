import Foundation

/// 共有家計簿向けの「よく使う取引」テンプレート
struct SharedFrequentTransactionTemplate: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var amount: Int
    var type: TransactionType
    var memo: String
    var categoryRecordName: String
    var tags: [String]

    func isEquivalent(to other: SharedFrequentTransactionTemplate) -> Bool {
        return amount == other.amount
        && type == other.type
        && memo == other.memo
        && categoryRecordName == other.categoryRecordName
        && tags == other.tags
    }
}
