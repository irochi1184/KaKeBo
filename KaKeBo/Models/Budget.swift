import Foundation

struct Budget: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var monthId: String // e.g. "2025-09"
    var categoryId: UUID
    var limitAmount: Int
}