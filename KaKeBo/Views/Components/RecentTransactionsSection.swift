//
//  Views/ComponentsRecentTransactionsSection.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct RecentTransactionsSection: View {
    @EnvironmentObject var store: DataStore
    let transactions: [Transaction]
    let categories: [Category]
    
    // 行高さ（見た目に合わせて微調整OK）
    private let rowHeight: CGFloat = 20
    // 最大高さ（カード内でスクロールさせたくないなら少し大きめでもOK）
    private let maxListHeight: CGFloat = 720
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近の履歴")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            if transactions.isEmpty {
                Text("まだ取引がありません")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                // 必要な高さを計算して明示的に指定
                let needed = CGFloat(transactions.count) * (rowHeight * 2) + 6
                List {
                    ForEach(transactions) { tx in
                        if let cat = categories.first(where: { $0.id == tx.categoryId }) {
                            TransactionRow(tx: tx, category: cat)
                                .frame(height: rowHeight)
                                .listRowBackground(Color.clear)       // カードと馴染ませる
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        store.deleteTransaction(id: tx.id)
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true) // 親ScrollViewにスクロールを任せる
                .frame(height: min(needed, maxListHeight)) // ← ここがキモ！
                .background(Color.clear)
            }
        }
    }
}

private struct TransactionRow: View {
    let tx: Transaction
    let category: Category
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(category.color.opacity(0.12))
                Image(systemName: category.symbolName)
                    .foregroundStyle(category.color)
            }
            .frame(width: 36, height: 36)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name).font(.subheadline.weight(.medium))
                if !tx.memo.isEmpty {
                    Text(tx.memo).font(.caption).foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(currency(tx.amount))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tx.type == .income ? .green : .primary)
                Text(dateStr(tx.date))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
    private func dateStr(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "M/d(EEE)"
        return f.string(from: d)
    }
}
