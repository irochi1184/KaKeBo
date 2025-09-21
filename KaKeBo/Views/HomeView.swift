import SwiftUI

struct HomeView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("今月の収支")
                        Spacer()
                        Text("¥" + String(currentMonthBalance()))
                            .bold()
                    }
                }

                Section("履歴") {
                    ForEach(store.transactions) { tx in
                        if let cat = store.categories.first(where: { $0.id == tx.categoryId }) {
                            HStack(spacing: 12) {
                                Image(systemName: cat.symbolName)
                                    .foregroundStyle(cat.color)
                                    .frame(width: 28)
                                VStack(alignment: .leading) {
                                    Text(cat.name)
                                    Text(tx.memo).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("¥\(tx.amount)")
                                    .foregroundStyle(tx.type == .income ? .green : .primary)
                            }
                        }
                    }
                    .onDelete(perform: store.deleteTransactions)
                }
            }
            .navigationTitle("KaKeBo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                // ここで初期カテゴリIDを渡す（描画前に @State が埋まる）
                AddTransactionView(defaultCategoryId: store.categories.first?.id)
                    .environmentObject(store)
            }

        }
    }

    private func currentMonthBalance() -> Int {
        let cal = Calendar.current
        let now = Date()
        return store.transactions.filter { cal.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { partial, tx in
                partial + (tx.type == .income ? tx.amount : -tx.amount)
            }
    }
}
