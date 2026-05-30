import Foundation

struct Budget: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var monthId: String // e.g. "2025-09"
    var categoryId: UUID
    var limitAmount: Int
    /// 予算管理が有効か。false の場合は金額を保持したまま
    /// 総予算・アラート・予測の対象から除外する（一時停止）
    var isEnabled: Bool = true

    init(id: UUID = UUID(), monthId: String, categoryId: UUID, limitAmount: Int, isEnabled: Bool = true) {
        self.id = id
        self.monthId = monthId
        self.categoryId = categoryId
        self.limitAmount = limitAmount
        self.isEnabled = isEnabled
    }

    // 旧データ（isEnabled キーなし）との後方互換のためのカスタムデコード
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        monthId = try c.decode(String.self, forKey: .monthId)
        categoryId = try c.decode(UUID.self, forKey: .categoryId)
        limitAmount = try c.decode(Int.self, forKey: .limitAmount)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
    }
}
