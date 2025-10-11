//
//  Views/Calendar/DayDetailSheet.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/23.
//

import SwiftUI

import SwiftUI

struct DayDetailSheet: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    
    let date: Date
    private var cal: Calendar { .current }
    
    @State private var editingTx: Transaction? = nil
    @State private var showAdd = false
    
    private var dayTx: [Transaction] {
        store.transactions
            .filter { cal.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date > $1.date }
    }
    
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                if dayTx.isEmpty {
                    ContentUnavailableView(
                        "この日には記録がありません",
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(dateTitle)
                    )
                    .padding()
                } else {
                    List {
                        ForEach(dayTx) { tx in
                            if let cat = store.categories.first(where: { $0.id == tx.categoryId }) {
                                
                                // 行全体タップで編集
                                Button { editingTx = tx } label: {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(cat.color.opacity(0.12))
                                            Image(systemName: cat.symbolName).foregroundStyle(cat.color)
                                        }
                                        .frame(width: 32, height: 32)
                                        
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
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                // スワイプ：編集／削除（確認なし）
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        editingTx = tx
                                    } label: {
                                        Label("編集", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                    
                                    Button(role: .destructive) {
                                        store.deleteTransactions(with: [tx.id])
                                    } label: {
                                        Label("削除", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        // 右上の EditButton（編集モード）での削除にも対応
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
                ToolbarItemGroup(placement: .topBarTrailing) {
                    // 編集モード切替（削除可）
                    EditButton().disabled(dayTx.isEmpty)
                    // 追加（＋）
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                            .imageScale(.large)
                    }
                }
            }
            // 編集シート
            .sheet(item: $editingTx) { tx in
                EditTransactionView(transaction: tx)
                    .environmentObject(store)
            }
            // その日の新規追加
            .sheet(isPresented: $showAdd) {
                AddTransactionView(
                    defaultCategoryId: store.categories.first?.id,
                    defaultDate: date,
                    defaultType: .expense
                )
                .environmentObject(store)
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
    
    // EditButton（編集モード）時の削除（確認なし）
    private func delete(at offsets: IndexSet) {
        let ids = offsets.map { dayTx[$0].id }
        store.deleteTransactions(with: ids)
    }
}
