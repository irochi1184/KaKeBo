//
//  Views/SettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/22.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: DataStore
    
    @AppStorage("reminder.enabled") private var enabled: Bool = true
    @AppStorage("reminder.time") private var timeRaw: Double = defaultTime.timeIntervalSinceReferenceDate
    
    @Environment(\.dismiss) private var dismiss
    @State private var notifAuthorized = false
    
    private static var defaultTime: Date {
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
                        .onChange(of: enabled) { _, _ in
                            Task { await applyScheduling() }
                        }
                    
                    DatePicker("時刻",
                               selection: .init(
                                get: { selectedTime },
                                set: { newVal in
                                    timeRaw = newVal.timeIntervalSinceReferenceDate
                                    Task { await applyScheduling() }
                                }
                               ),
                               displayedComponents: .hourAndMinute)
                    .disabled(!enabled)
                }
            }
            .navigationTitle("設定")
            .task {
                // 初回に通知許可を取得
                notifAuthorized = await ReminderManager.requestAuthorization()
                if enabled { await applyScheduling() }
            }
        }
    }
    
    private func applyScheduling() async {
        if enabled {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: selectedTime)
            await ReminderManager.scheduleDaily(hour: comps.hour ?? 21, minute: comps.minute ?? 0)
        } else {
            await ReminderManager.cancel(id: ReminderManager.dailyId)
        }
    }
}
