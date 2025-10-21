//
//  Views/Components/YearMonthHeader.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct YearMonthHeader: View {
    @Binding var month: Date
    let title: String
    
    /// テーマ管理で決めたアクセント色
    var accent: Color = .accentColor
    
    @State private var showPicker = false
    @Environment(\.locale) private var locale
    
    var body: some View {
        HStack(spacing: 16) {
            
            // 前月へ
            Button {
                withAnimation(.snappy) {
                    month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.callout)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }
            
            // 中央タイトル（背景はテーマ色の薄い色）
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                    
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accent)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(accent.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPicker, arrowEdge: .top) {
                MonthPickerView(selected: $month, accent: accent)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .padding()
            }
            
            // 次月へ
            Button {
                withAnimation(.snappy) {
                    month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.callout)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

// “月だけ”を選ぶシンプルなピッカー（年＆月）
private struct MonthPickerView: View {
    @Binding var selected: Date
    @State private var year: Int
    @State private var month: Int
    @Environment(\.dismiss) private var dismiss
    var accent: Color = .accentColor
    
    init(selected: Binding<Date>, accent: Color = .accentColor) {
        _selected = selected
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: selected.wrappedValue)
        _year = State(initialValue: comps.year ?? cal.component(.year, from: .now))
        _month = State(initialValue: comps.month ?? cal.component(.month, from: .now))
        self.accent = accent
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("対象月を選択")
                .font(.headline)
            
            HStack {
                Picker("年", selection: $year) {
                    ForEach((2000...2100), id: \.self) { y in
                        Text("\(String(y))年").tag(y)
                    }
                }
                .pickerStyle(.wheel)
                
                Picker("月", selection: $month) {
                    ForEach(1...12, id: \.self) { m in
                        Text("\(m)月").tag(m)
                    }
                }
                .pickerStyle(.wheel)
            }
            .frame(height: 160)
            
            Button {
                let cal = Calendar.current
                if let newDate = cal.date(from: DateComponents(year: year, month: month, day: 1)) {
                    selected = newDate
                }
                dismiss()
            } label: {
                Text("決定")
                    .frame(maxWidth: .infinity, minHeight: 35)
                    .font(.headline)
                    .foregroundColor(.white)
                    .background(accent)
                    .cornerRadius(12)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
    }
}
