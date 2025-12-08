//
//  Views/Components/LedgerModePicker.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/12/09.
//

import SwiftUI

enum LedgerModePickerStyle {
    case circleIcon   // ← AllTransactionView 用（フィルターボタン風）
    case compact      // ← 今まで通りの小さめ表示などに使う想定
}

struct LedgerModePicker: View {
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    
    var style: LedgerModePickerStyle = .compact

    var body: some View {
        let accent = themeStore.theme.accentColor(for: scheme)
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

                            Label {
                                Text(ledger.name)
                            } icon: {
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                } else {
                                    Image(systemName: ledger.icon)
                                }
                            }
                        }
                    }
                }
            } else {
                Text("共有家計簿なし")
                    .foregroundStyle(.secondary)
            }
        } label: {
            switch style {
            case .circleIcon:
                if #available(iOS 26.0, *) {
                    Image(systemName: ledgerContext.isPersonal ? "person" : "person.2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                        .glassEffect(.clear.tint(.gray.opacity(0.2)).interactive())
                } else {
                    Image(systemName: ledgerContext.isPersonal ? "person" : "person.2.fill")
                        .imageScale(.large)
                        .foregroundStyle(Color.accentColor)  // 親の .tint に追従
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(Color.accentColor.opacity(0.12))
                                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.8))
                        )
                }

            case .compact:
                // ← 今まで使っていたスタイル（お好みで調整）
                HStack(spacing: 4) {
                    Image(systemName: ledgerContext.isPersonal ? "person" : "person.2.fill")
                }
                .font(.subheadline)
            }
        }
    }
}
