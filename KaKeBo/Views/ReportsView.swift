import SwiftUI

struct ReportsView: View {
    @EnvironmentObject var store: DataStore

    var body: some View {
        List {
            Section("月別サマリ") {
                ForEach(months(), id: \.self) { monthId in
                    HStack {
                        Text(monthId)
                        Spacer()
                        Text("¥\(sum(for: monthId))")
                    }
                }
            }
        }
        .navigationTitle("レポート")
    }

    private func months() -> [String] {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        let set = Set(store.transactions.map { fmt.string(from: $0.date) })
        return set.sorted()
    }

    private func sum(for monthId: String) -> Int {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM"
        return store.transactions.filter { fmt.string(from: $0.date) == monthId }
            .reduce(0) { $0 + ($1.type == .income ? $1.amount : -$1.amount) }
    }
}