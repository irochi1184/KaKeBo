//
//  Settings/ReminderRuleEditor.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI

struct ReminderRuleEditor: View {
    @State var rule: ReminderRule
    let onSave: (ReminderRule) -> Void
    @Environment(\.dismiss) private var dismiss
    
    // 課金状態 & テーマ
    @EnvironmentObject var purchase: PurchaseManager
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @State private var showPaywall = false
    @State private var previewUsesFallback = false
    
    // プレビュー用
    var previewTodosToday: Int = 2
    var previewUnloggedToday: Bool = true
    
    private let weekdaysJP = ["日", "月", "火", "水", "木", "金", "土"]
    
    var body: some View {
        let accent = themeStore.theme.accentColor(for: scheme)
        Form {
            // ===== スケジュール（常に利用可） =====
            Section("スケジュール") {
                Picker("繰り返し", selection: $rule.repeatType) {
                    Text("毎日").tag(ReminderRepeat.daily)
                    Text("毎週").tag(ReminderRepeat.weekly)
                }
                .pickerStyle(.segmented)
                
                if rule.repeatType == .weekly {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("通知する曜日").font(.subheadline)
                        HStack {
                            ForEach(1...7, id: \.self) { i in
                                Button {
                                    if rule.weekdays.contains(i) {
                                        rule.weekdays.remove(i)
                                    } else {
                                        rule.weekdays.insert(i)
                                    }
                                } label: {
                                    Text(weekdaysJP[i - 1])
                                        .frame(width: 30, height: 30)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(rule.weekdays.contains(i) ? .white : .primary)
                                        .background(
                                            Circle()
                                                .fill(rule.weekdays.contains(i) ? accent : .gray.opacity(0.2))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                DatePicker("時刻", selection: $rule.time, displayedComponents: .hourAndMinute)
                Toggle("有効", isOn: $rule.enabled)
                Toggle("通知音を鳴らす", isOn: $rule.soundEnabled)
            }
            
            // ===== プレミアム限定：通知メッセージ + プレビュー =====
            if purchase.isPremiumActive {
                Section("通知メッセージ") {
                    TextField("通知タイトル（例：今日の家計簿をつけましょう）", text: $rule.title)
                    Text("タイトルにもプレースホルダーを使えます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("通知メッセージ（例：今日の支出・収入を登録しましょう。{todosToday}件のToDo）",
                                  text: $rule.bodyTemplate, axis: .vertical)
                        .lineLimit(2...4)
                        
                        // ワンタップ挿入チップ
                        PlaceholderChips(target: $rule.bodyTemplate)
                        
                        Text("プレースホルダーは、通知時に実際の値に置き換わります。")
                            .font(.caption).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(ReminderPlaceholder.allCases) { p in
                                Text("• \(p.rawValue) ＝ \(p.labelJP)（\(p.hintJP)）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                Section("プレビュー") {
                    let preview = resolvedBodyPreview(useFallback: previewUsesFallback)
                    if rule.onlyIfUnloggedToday || rule.onlyIfTodosDueToday {
                        Toggle("条件不一致の本文をプレビュー", isOn: $previewUsesFallback)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        let previewTitle = resolvedTextPreview(rule.title)
                        Text(previewTitle.isEmpty ? "（タイトル未入力）" : previewTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(preview.isEmpty ? "（本文未入力）" : preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
                }
            } else {
                // 無料ユーザーにはロック表示
                Section {
                    LockedPremiumRow(
                        title: "プレミアムプラン加入で通知メッセージのカスタムや通知条件の設定が利用可能になります。",
                        accent: accent
                    ) { showPaywall = true }
                } header: { Text("プレミアム機能") }
            }
            
            // ===== プレミアム限定：条件 =====
            if purchase.isPremiumActive {
                Section("条件") {
                    Toggle("今日の取引が未登録の時だけ通知", isOn: $rule.onlyIfUnloggedToday)
                    Toggle("今日が期日のToDoがある時だけ通知", isOn: $rule.onlyIfTodosDueToday)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("条件不一致時の本文")
                            .font(.subheadline)
                        TextField("条件に一致しない場合の本文", text: $rule.fallbackBodyTemplate, axis: .vertical)
                            .lineLimit(2...4)
                        Text("空欄の場合は通常本文を使用します。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("リマインダーを編集")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") { onSave(rule) }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    // 置換してプレビュー用本文を作る（プレミアム時のみに使われる）
    private func resolvedBodyPreview(useFallback: Bool) -> String {
        let template = (useFallback && (rule.onlyIfUnloggedToday || rule.onlyIfTodosDueToday))
            ? (rule.fallbackBodyTemplate.isEmpty ? rule.bodyTemplate : rule.fallbackBodyTemplate)
            : rule.bodyTemplate
        return resolvedTextPreview(template)
    }

    private func resolvedTextPreview(_ template: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")
        dateFormatter.dateFormat = "M/d"
        let weekdaySymbols = Calendar.current.shortStandaloneWeekdaySymbols
        let weekdayIndex = Calendar.current.component(.weekday, from: Date())
        let weekdaySymbol = weekdaySymbols[(weekdayIndex - 1) % weekdaySymbols.count]
        return template
            .replacingOccurrences(of: ReminderPlaceholder.todosToday.rawValue,
                                  with: "\(previewTodosToday)")
            .replacingOccurrences(of: ReminderPlaceholder.unloggedToday.rawValue,
                                  with: previewUnloggedToday ? "はい" : "いいえ")
            .replacingOccurrences(of: ReminderPlaceholder.todayDate.rawValue,
                                  with: dateFormatter.string(from: Date()))
            .replacingOccurrences(of: ReminderPlaceholder.todayWeekday.rawValue,
                                  with: weekdaySymbol)
    }
}

// ロック行（ボタン付き）
private struct LockedPremiumRow: View {
    let title: String
    let accent: Color
    let onTapUpgrade: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(accent)
            Text(title)
            Spacer()
            Button("プレミアムを確認", action: onTapUpgrade)
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .padding(6)
    }
}

// ワンタップで本文末尾にプレースホルダーを挿入
private struct PlaceholderChips: View {
    @Binding var target: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ReminderPlaceholder.allCases) { p in
                    Button {
                        if !target.isEmpty, target.last?.isWhitespace == false { target += " " }
                        target += p.rawValue
                    } label: {
                        Text(p.labelJP)
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
