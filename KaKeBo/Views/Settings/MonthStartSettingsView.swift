//
//  Views/Settings/MonthStartSettingsView.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/02/23.
//

import SwiftUI

struct MonthStartSettingsView: View {
    @EnvironmentObject var monthStartStore: MonthStartStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    private var resolver: MonthStartResolver {
        monthStartStore.resolver()
    }

    private var previewText: String {
        let start = resolver.startDate(for: Date())
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M月d日（E）から"
        return f.string(from: start)
    }

    var body: some View {
        Form {
            Section(header: Text("基本設定")) {
                Toggle("カスタム開始日を使う", isOn: Binding(
                    get: { monthStartStore.settings.isCustomStartEnabled },
                    set: { monthStartStore.settings.isCustomStartEnabled = $0 }
                ))

                if monthStartStore.settings.isCustomStartEnabled {
                    Stepper(value: Binding(
                        get: { monthStartStore.settings.startDay },
                        set: { monthStartStore.settings.startDay = min(max($0, 1), 31) }
                    ), in: 1...31) {
                        Text("毎月\(monthStartStore.settings.startDay)日から始める")
                    }

                    Picker("土日祝日に当たる場合", selection: Binding(
                        get: { monthStartStore.settings.holidayAdjustment },
                        set: { monthStartStore.settings.holidayAdjustment = $0 }
                    )) {
                        ForEach(MonthStartAdjustment.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section(header: Text("プレビュー"), footer: Text("春分・秋分などを含めた日本の祝日と土日を判定して開始日を調整します。")) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.secondary)
                    Text(previewText)
                    Spacer()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(themeColor)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("閉じる") { dismiss() }
            }
        }
    }

    private var themeColor: Color {
        scheme == .dark ? Color.black.opacity(0.8) : Color(UIColor.systemGroupedBackground)
    }
}
