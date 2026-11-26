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
    static let desk = Color(red: 0.87, green: 0.89, blue: 0.82)
    static let sheet = Color(red: 0.982, green: 0.973, blue: 0.936)
    static func yen(_ amount: Int) -> String {
        "¥" + amount.formatted(.number.locale(Locale(identifier: "ja_JP")))
    }
}

struct PaperSurface: View {
    var base = Paper.sheet
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            // A fixed grain pattern stays still when the form redraws.
            var grain = Path()
            var seed: UInt32 = 12345
            func sample() -> CGFloat {
                seed = seed &* 1664525 &+ 1013904223
                return CGFloat(seed) / CGFloat(UInt32.max)
            }
            for _ in 0..<min(5000, Int(size.width * size.height / 28)) {
                grain.addRect(CGRect(x: sample() * size.width, y: sample() * size.height, width: 1.1, height: 0.6))
            }
            context.fill(grain, with: .color(.brown.opacity(0.09)))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct ReceiptEdge: Shape {
    var stub = false
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cut: CGFloat = stub ? 5 : 15
        var p = Path()
        p.move(to: CGPoint(x: 0, y: cut))
        p.addLine(to: CGPoint(x: cut, y: 0))
        p.addLine(to: CGPoint(x: w-cut, y: 0))
        p.addLine(to: CGPoint(x: w, y: cut))
        if stub {
            p.addLine(to: CGPoint(x: w, y: h/2-5))
            p.addQuadCurve(to: CGPoint(x: w, y: h/2+5), control: CGPoint(x: w-9, y: h/2))
        }
        p.addLine(to: CGPoint(x: w, y: h))
        let count = max(1, Int(w / 11))
        let step = w / CGFloat(count)
        for i in (0..<count).reversed() {
            p.addQuadCurve(to: CGPoint(x: CGFloat(i)*step, y: h),
                           control: CGPoint(x: (CGFloat(i)+0.5)*step, y: h-7))
        }
        if stub {
            p.addLine(to: CGPoint(x: 0, y: h/2+5))
            p.addQuadCurve(to: CGPoint(x: 0, y: h/2-5), control: CGPoint(x: 9, y: h/2))
        }
        p.closeSubpath()
        return p
    }
}

struct Bookmark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero); p.addLine(to: CGPoint(x: r.width, y: 0))
        p.addLine(to: CGPoint(x: r.width, y: r.height))
        p.addLine(to: CGPoint(x: r.midX, y: r.height * 0.73))
        p.addLine(to: CGPoint(x: 0, y: r.height)); p.closeSubpath()
        return p
    }
    static let gold = Color(red: 0.73, green: 0.59, blue: 0.23)
}

struct Perforation: View {
    var body: some View {
        GeometryReader { geo in
            Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: geo.size.width, y: 0)) }
                .stroke(Paper.ink.opacity(0.38), style: StrokeStyle(lineWidth: 0.7, dash: [1, 3]))
        }.frame(height: 1)
    }
}

struct VoucherButtonStyle: ButtonStyle {
    var filled = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(filled ? Color.white : Paper.ink)
            .background(filled ? (enabled ? Paper.ink : Color.gray.opacity(0.45)) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 13))
            .overlay { if !filled { RoundedRectangle(cornerRadius: 13).strokeBorder(Paper.ink) } }
            .opacity(configuration.isPressed ? 0.75 : 1)
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
