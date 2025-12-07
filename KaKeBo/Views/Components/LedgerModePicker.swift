//
//  Views/Components/LedgerModePicker.swift
//  KaKeBo
//
//  Created by OpenAI ChatGPT on 2025/12/09.
//

import SwiftUI

struct LedgerModePicker: View {
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore

    var body: some View {
        Menu {
            // 個人用
            Button {
                ledgerContext.setPersonal()
            } label: {
                Label(
                    "個人用家計簿",
                    systemImage: ledgerContext.isPersonal ? "checkmark.circle.fill" : "person"
                )
            }

            // 共有家計簿一覧
            if !sharedLedgerStore.ledgers.isEmpty {
                Section("共有家計簿") {
                    ForEach(sharedLedgerStore.ledgers) { ledger in
                        Button {
                            ledgerContext.setShared(id: ledger.id)
                            Task {
                                await sharedLedgerStore.reloadTransactions(for: ledger)
                            }
                        } label: {
                            let isSelected =
                            ledgerContext.isShared &&
                            ledgerContext.selectedSharedLedgerId == ledger.id

                            Label(
                                ledger.name,
                                systemImage: isSelected ? "checkmark.circle.fill" : "person.2"
                            )
                        }
                    }
                }
            } else {
                Text("共有家計簿なし")
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: ledgerContext.isPersonal ? "person" : "person.2.fill")
                Text(ledgerContext.isPersonal ? "個人用" : "共有")
            }
            .font(.subheadline)
        }
    }
}
