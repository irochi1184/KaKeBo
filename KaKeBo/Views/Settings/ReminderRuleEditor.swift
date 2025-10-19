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
    // プレビュー用の現在値を親から渡す（設定画面側で計算）
    var previewTodosToday: Int = 2
    var previewUnloggedToday: Bool = true
    
    private let weekdaysJP = ["日", "月", "火", "水", "木", "金", "土"]
    
    var body: some View {
        Form {
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
                                                .fill(rule.weekdays.contains(i) ? .blue : .gray.opacity(0.2))
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
            }
            
            Section("通知メッセージ") {
                TextField("通知タイトル（例：今日の家計簿をつけましょう）", text: $rule.title)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("通知メッセージ（例：今日の支出・収入を登録しましょう。"
                              + "¥n残りToDo: {todosToday}）",
                              text: $rule.bodyTemplate, axis: .vertical)
                    .lineLimit(2...4)
                    
                    // ← ここが“ワンタップ挿入”チップ
                    PlaceholderChips(target: $rule.bodyTemplate)
                    
                    // わかりやすい説明
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
                let preview = resolvedBodyPreview()
                VStack(alignment: .leading, spacing: 6) {
                    Text(rule.title.isEmpty ? "（タイトル未入力）" : rule.title)
                        .font(.subheadline.weight(.semibold))
                    Text(preview.isEmpty ? "（本文未入力）" : preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
            }
            
            Section("条件") {
                Toggle("今日の取引が未登録の時だけ通知", isOn: $rule.onlyIfUnloggedToday)
                Toggle("今日が期日のToDoがある時だけ通知", isOn: $rule.onlyIfTodosDueToday)
            }
        }
        .navigationTitle("リマインダーを編集")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) { Button("保存") { onSave(rule) } }
        }
    }
    
    // 置換してプレビュー用本文を作る
    private func resolvedBodyPreview() -> String {
        var body = rule.bodyTemplate
        body = body.replacingOccurrences(of: ReminderPlaceholder.todosToday.rawValue,
                                         with: "\(previewTodosToday)")
        //        body = body.replacingOccurrences(of: ReminderPlaceholder.unloggedToday.rawValue,
        //                                         with: previewUnloggedToday ? "はい" : "いいえ")
        return body
    }
}

// ワンタップで本文末尾にプレースホルダーを挿入（シンプル実装）
private struct PlaceholderChips: View {
    @Binding var target: String
    var body: some View {
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
