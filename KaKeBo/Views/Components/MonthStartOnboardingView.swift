//
//  Views/Components/MonthStartOnboardingView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/12/08.
//

import SwiftUI

struct MonthStartOnboardingView: View {
    @Binding var settings: MonthStartSettings
    let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var resolver: MonthStartResolver {
        MonthStartResolver(settings: settings, holidayProvider: JapaneseHolidayProvider())
    }

    private var previewText: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "M月d日（E）"
        let range = resolver.monthRange(for: Date())
        return "\(f.string(from: range.lowerBound)) 〜 \(f.string(from: range.upperBound))"
    }

    private var boundaryLabel: String {
        settings.boundaryType == .startDay ? "開始日" : "締め日"
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("家計管理を自分のサイクルに合わせましょう")
                    .font(.headline)
                Text("月の開始日・締め日を決めると、ホームの集計やグラフがその日を基準に表示されます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("カスタム開始日を使う", isOn: Binding(
                    get: { settings.isCustomStartEnabled },
                    set: { settings.isCustomStartEnabled = $0 }
                ))

                if settings.isCustomStartEnabled {
                    Picker("集計の基準", selection: Binding(
                        get: { settings.boundaryType },
                        set: { settings.boundaryType = $0 }
                    )) {
                        ForEach(MonthBoundaryType.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker(boundaryLabel, selection: Binding(
                        get: { settings.startDay },
                        set: { settings.startDay = $0 }
                    )) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)日").tag(day)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("土日祝日に当たる場合", selection: Binding(
                        get: { settings.holidayAdjustment },
                        set: { settings.holidayAdjustment = $0 }
                    )) {
                        ForEach(MonthStartAdjustment.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("今月は \(previewText) の期間で集計されます。")
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )

            Spacer()

            VStack(spacing: 12) {
                Button(role: .cancel) {
                    onFinish()
                    dismiss()
                } label: {
                    Text("あとで決める")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    onFinish()
                    dismiss()
                } label: {
                    Text(settings.isCustomStartEnabled ? "この設定で開始する" : "1日開始で続ける")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
