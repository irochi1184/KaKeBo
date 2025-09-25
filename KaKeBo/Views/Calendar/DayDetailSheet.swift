//
//  Views/Calendar/DayDetailSheet.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/23.
//

import SwiftUI

struct DayDetailSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    
    let date: Date
    private var cal: Calendar { Calendar.current }
    
    private var dayTx: [Transaction] {
        store.transactions
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                if dayTx.isEmpty {
                    ContentUnavailableView("この日には記録がありません", systemImage: "calendar.badge.exclamationmark", description: Text(dateTitle))
                        .padding()
                } else {
                    List {
                        ForEach(dayTx) { tx in
                            if let cat = store.categories.first(where: { $0.id == tx.categoryId }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(cat.color.opacity(0.12))
                                        Image(systemName: cat.symbolName).foregroundStyle(cat.color)
                                    }.frame(width: 32, height: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat.name).font(.subheadline.weight(.medium))
                                        if !tx.memo.isEmpty {
                                            Text(tx.memo).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Text(currency(tx.amount))
                                        .foregroundStyle(tx.type == .income ? .green : .primary)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(dateTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton().disabled(dayTx.isEmpty)
                }
            }
        }
    }
    
    private var dateTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M月d日(EEE)"
        return f.string(from: date)
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
    
    private func delete(at offsets: IndexSet) {
        // 表示中の dayTx から削除対象の id を取得
        let ids = offsets.map { dayTx[$0].id }
        for id in ids {
            store.deleteTransaction(id: id)
        }
    }
}
