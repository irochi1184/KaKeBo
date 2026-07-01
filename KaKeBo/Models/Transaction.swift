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
    /// 添付写真のファイル名（AppGroup コンテナ内 `Photos/` 配下に保存された実体への参照）。
    /// 旧データとの互換のためオプショナル。nil/空は写真なし。
    var photoFilenames: [String]? = nil
}
