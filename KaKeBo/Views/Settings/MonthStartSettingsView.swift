//
//  Views/Settings/MonthStartSettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/12/08.
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
        let range = resolver.monthRange(for: Date())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日（E）"
        return "\(formatter.string(from: range.lowerBound)) 〜 \(formatter.string(from: range.upperBound)) の期間で集計されます。"
    }

    private var boundaryLabel: String {
        monthStartStore.settings.boundaryType == .startDay ? "開始日" : "締め日"
    }

    var body: some View {
        Form {
            Section(header: Text("基本設定")) {
                Toggle("カスタム開始日を使う", isOn: Binding(
                    get: { monthStartStore.settings.isCustomStartEnabled },
                    set: { monthStartStore.settings.isCustomStartEnabled = $0 }
                ))

                if monthStartStore.settings.isCustomStartEnabled {

                    Picker("集計の基準", selection: Binding(
                        get: { monthStartStore.settings.boundaryType },
                        set: { monthStartStore.settings.boundaryType = $0 }
                    )) {
                        ForEach(MonthBoundaryType.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    // MARK: - 開始日の選択（チップスタイル）
                    VStack(alignment: .leading, spacing: 8) {
                        Text(boundaryLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(1...31, id: \.self) { day in
                                    let isSelected = (day == monthStartStore.settings.startDay)
                                    
                                    Button {
                                        monthStartStore.settings.startDay = day
                                    } label: {
                                        Text("\(day)日")
                                            .font(.callout)
                                            .padding(.vertical, 6)
                                            .padding(.horizontal, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .fill(isSelected
                                                          ? Color.accentColor.opacity(0.18)
                                                          : Color(.systemGray5))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(2)
                        }
                    }
                    .padding(.vertical, 4)

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
        .listRowBackground(FlatListRowBackground())
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
