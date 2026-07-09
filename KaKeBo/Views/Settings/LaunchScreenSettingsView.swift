//
//  Views/Settings/LaunchScreenSettingsView.swift
//  KaKeBo
//
//  起動時に最初に表示する画面の設定
//

import SwiftUI

struct LaunchScreenSettingsView: View {
    @AppStorage(LaunchScreenOption.storageKey, store: .appGroup)
    private var launchScreenRaw = LaunchScreenOption.home.rawValue

    let accent: Color
    @Environment(\.dismiss) private var dismiss

    private var selection: LaunchScreenOption {
        LaunchScreenOption(rawValue: launchScreenRaw) ?? .home
    }

    var body: some View {
        List {
            Section {
                ForEach(LaunchScreenOption.allCases) { option in
                    Button {
                        launchScreenRaw = option.rawValue
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: option.symbol)
                                .foregroundStyle(selection == option ? accent : .secondary)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.title)
                                    .foregroundStyle(.primary)
                                Text(option.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection == option {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("次回のアプリ起動時から適用されます。ウィジェットから起動した場合はウィジェットの画面が優先されます。")
            }
        }
        .listStyle(.insetGrouped)
        .listRowBackground(FlatListRowBackground(appliesFlatBorder: false))
        .navigationTitle("起動時に開く画面")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") { dismiss() }
            }
        }
    }
}
