//
//  Views/ReminderSettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/23.
//

import SwiftUI

struct ReminderSettingsView: View {
    @AppStorage("reminder.enabled") private var enabled: Bool = true
    @AppStorage("reminder.time") private var timeRaw: Double = defaultTime.timeIntervalSinceReferenceDate
    @Environment(\.dismiss) private var dismiss
    
    @State private var authGranted = false
    
    private static var defaultTime: Date {
        // 夜9時
        var comps = DateComponents()
        comps.hour = 21; comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
    
    private var selectedTime: Date {
        get { Date(timeIntervalSinceReferenceDate: timeRaw) }
        set { timeRaw = newValue.timeIntervalSinceReferenceDate }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("リマインダー") {
                    Toggle("毎日通知する", isOn: $enabled)
                        .onChange(of: enabled) { _, newValue in
                            Task { await applyScheduling() }
                        }
                    
                    DatePicker("時刻", selection: .init(
                        get: { selectedTime },
                        set: { newVal in
                            timeRaw = newVal.timeIntervalSinceReferenceDate
                            Task { await applyScheduling() }
                        }
                    ), displayedComponents: .hourAndMinute)
                    .disabled(!enabled)
                }
            }
            .navigationTitle("設定")
            .task {
                // 起動時に権限チェック（付与されてなければリクエスト）
                authGranted = await ReminderManager.requestAuthorization()
                if enabled { await applyScheduling() }
            }
        }
    }
    
    private func applyScheduling() async {
        guard enabled else {
            await ReminderManager.cancel(id: ReminderManager.dailyId)
            return
        }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
        await ReminderManager.scheduleDaily(hour: comps.hour ?? 21, minute: comps.minute ?? 0)
    }
}
