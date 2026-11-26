import SwiftUI

enum Kind: String, Codable, CaseIterable, Identifiable {
    case expense = "支出", income = "収入"
    var id: Self { self }
}

struct LedgerCategory: Identifiable {
    let name: String
    let symbol: String
    let color: Color
    var id: String { name }

    init(_ name: String, _ symbol: String, _ color: Color) {
        self.name = name
        self.symbol = symbol
        self.color = color
    }

    static let expenses: [Self] = [
        .init("食費", "fork.knife", .orange), .init("日用品費", "bag", .yellow),
        .init("交通費", "tram", .cyan), .init("通信料", "wifi", .purple),
        .init("住宅費", "house", .blue), .init("交際費", "gift", .teal),
        .init("娯楽費", "gamecontroller", .green), .init("電気代", "bolt", .yellow),
        .init("ガス代", "flame", .orange), .init("車両費", "car", .orange),
        .init("雑費", "ellipsis.circle", .gray), .init("外食", "fork.knife", .pink),
        .init("カフェ代", "cup.and.saucer", .brown), .init("サブスク", "display", .teal),
        .init("おやつ代", "takeoutbag.and.cup.and.straw", .pink), .init("保険", "leaf", .green),
        .init("学費", "graduationcap", .red), .init("投資", "building.columns", .indigo),
        .init("駐車場代", "parkingsign.circle", .mint)
    ]
    static func options(_ kind: Kind) -> [Self] {
        kind == .expense ? expenses : [.init("給与", "banknote", .teal), .init("その他収入", "yensign.circle", .blue)]
    }
}

struct Voucher: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let kind: Kind
    let category: String
    let amount: Int
    let memo: String
}

@MainActor
final class Ledger: ObservableObject {
    @Published private(set) var entries: [Voucher] = []
    @Published var problem: String?
    private(set) var ready = false
    private let file: URL

    init() {
        file = URL.applicationSupportDirectory.appending(path: "prototype-vouchers-v1.json")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) {
                entries = try JSONDecoder().decode([Voucher].self, from: Data(contentsOf: file))
            } else {
                let now = Date()
                let samples = [
                    Voucher(date: now, kind: .expense, category: "食費", amount: 2800, memo: "見本・夕食の材料"),
                    Voucher(date: now, kind: .expense, category: "交通費", amount: 420, memo: "見本・電車"),
                    Voucher(date: now, kind: .expense, category: "カフェ代", amount: 500, memo: "見本・紅茶"),
                    Voucher(date: now, kind: .income, category: "給与", amount: 120000, memo: "見本")
                ]
                try write(samples)
            }
            ready = true
        } catch {
            problem = "試作データを開けませんでした。\n" + error.localizedDescription
        }
    }

    func append(_ item: Voucher) throws {
        guard ready else { throw CocoaError(.fileWriteNoPermission) }
        try write([item] + entries)
    }

    private func write(_ items: [Voucher]) throws {
        try JSONEncoder().encode(items).write(to: file, options: .atomic)
        entries = items
    }
}

enum Paper {
    static let ink = Color(red: 0.10, green: 0.28, blue: 0.19)
    static let desk = Color(red: 0.92, green: 0.94, blue: 0.89)
    static let sheet = Color(red: 1, green: 0.99, blue: 0.96)
    static func yen(_ amount: Int) -> String {
        "¥" + amount.formatted(.number.locale(Locale(identifier: "ja_JP")))
    }
}

struct ReceiptEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: 7))
        p.addLine(to: CGPoint(x: 7, y: 0))
        p.addLine(to: CGPoint(x: rect.width - 7, y: 0))
        p.addLine(to: CGPoint(x: rect.width, y: 7))
        let count = max(1, Int(rect.width / 12))
        let step = rect.width / CGFloat(count)
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - 3))
        for i in (0..<count).reversed() {
            p.addLine(to: CGPoint(x: (CGFloat(i) + 0.5) * step, y: rect.height))
            p.addLine(to: CGPoint(x: CGFloat(i) * step, y: rect.height - 3))
        }
        p.closeSubpath()
        return p
    }
}

struct CategoryLabel: View {
    let item: LedgerCategory
    var body: some View {
        HStack(spacing: 7) {
            Capsule().fill(item.color).frame(width: 4, height: 21)
            Image(systemName: item.symbol).frame(width: 21)
            Text(item.name).fixedSize(horizontal: false, vertical: true)
        }.foregroundStyle(.primary)
    }
}
