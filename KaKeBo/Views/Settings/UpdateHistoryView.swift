//
//  UpdateHistoryView.swift
//  KaKeBo
//
//  アップデート履歴を時系列で一覧表示するビュー
//

import SwiftUI

struct UpdateHistoryView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { themeStore.theme.accentColor(for: scheme) }

    var body: some View {
        List {
            ForEach(versionHistory) { entry in
                Section {
                    ForEach(entry.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(accent.opacity(0.7))
                                .frame(width: 6, height: 6)
                                .padding(.top, 7)
                            Text(item)
                                .font(.subheadline)
                        }
                    }
                } header: {
                    HStack(spacing: 8) {
                        Image(systemName: "app.badge.checkmark")
                            .foregroundStyle(accent)
                        Text("バージョン \(entry.version)")
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}
