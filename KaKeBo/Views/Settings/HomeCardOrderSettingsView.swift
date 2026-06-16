//
//  Views/Settings/HomeCardOrderSettingsView.swift
//  KaKeBo
//
//  ホーム画面に並ぶカードの「表示順」と「表示/非表示」を設定画面から編集する画面。
//  並び順は home.cardOrder、非表示カードは home.hiddenCards に保存する。
//

import SwiftUI

struct HomeCardOrderSettingsView: View {
    @Environment(\.colorScheme) private var scheme
    let accent: Color

    @State private var order: [DashboardCard] = CardOrderStore().load()
    @State private var hidden: Set<DashboardCard> = HiddenCardStore().load()

    private let orderStore = CardOrderStore()
    private let hiddenStore = HiddenCardStore()

    var body: some View {
        Form {
            Section {
                ForEach(order) { card in
                    HStack {
                        Label {
                            Text(card.title)
                                .foregroundStyle(hidden.contains(card) ? .secondary : .primary)
                        } icon: {
                            Image(systemName: card.systemImage)
                                .foregroundStyle(hidden.contains(card) ? Color.secondary : accent)
                        }
                        Spacer()
                        Toggle("", isOn: visibilityBinding(for: card))
                            .labelsHidden()
                            .tint(accent)
                    }
                }
                .onMove(perform: move)
            } header: {
                Text("ホーム画面のカード")
            } footer: {
                Text("スイッチでカードの表示/非表示を切り替えできます。右上の「編集」をタップすると並び順を変更できます（ホーム画面でカードを長押ししてドラッグしても並び替え可能）。\nオンにしていても、対象のデータがある月だけ表示されます。")
            }
            .listRowBackground(scheme == .dark ? Color.white.opacity(0.06) : .white)

            Section {
                Button {
                    withAnimation {
                        order = DashboardCard.defaultOrder
                        hidden = []
                    }
                    orderStore.save(order)
                    hiddenStore.save(hidden)
                } label: {
                    Label("初期状態に戻す", systemImage: "arrow.counterclockwise")
                        .foregroundStyle(accent)
                }
            }
            .listRowBackground(scheme == .dark ? Color.white.opacity(0.06) : .white)
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    /// カードの表示/非表示を切り替える Binding（オン=表示）
    private func visibilityBinding(for card: DashboardCard) -> Binding<Bool> {
        Binding(
            get: { !hidden.contains(card) },
            set: { isVisible in
                if isVisible {
                    hidden.remove(card)
                } else {
                    hidden.insert(card)
                }
                hiddenStore.save(hidden)
            }
        )
    }

    private func move(from source: IndexSet, to destination: Int) {
        order.move(fromOffsets: source, toOffset: destination)
        orderStore.save(order)
    }
}
