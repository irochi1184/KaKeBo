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
    
    @State private var showPicker = false
    @Environment(\.locale) private var locale
    
    var body: some View {
        HStack(spacing: 16) {
            
            Button {
                withAnimation(.snappy) {
                    month = Calendar.current.date(byAdding: .month, value: -1, to: month) ?? month
                }
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.callout)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            }
            
            // 中央タイトルボタン（色はシステムブルー or アクセントに合わせる）
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.blue)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.blue)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.thinMaterial)
                )
            }
            .buttonStyle(.plain)
            // iPad等は popover、iPhone等は sheet として出る
            .popover(isPresented: $showPicker, arrowEdge: .top) {
                MonthPickerView(selected: $month)
                    .presentationDetents([.medium]) // iPhoneでの見え方
                    .presentationDragIndicator(.visible)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .padding()
            }
            
            Button {
                withAnimation(.snappy) {
                    month = Calendar.current.date(byAdding: .month, value: 1, to: month) ?? month
                }
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.callout)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity)           // ← ヘッダーを中央に
        .contentShape(Rectangle())            // タップ余白を広く
        .accessibilityElement(children: .contain)
    }
}

// “月だけ”を選ぶシンプルなピッカー（年＆月）
private struct MonthPickerView: View {
    @Binding var selected: Date
    @State private var year: Int
    @State private var month: Int
    @Environment(\.dismiss) private var dismiss   // ← 追加
    
    init(selected: Binding<Date>) {
        _selected = selected
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: selected.wrappedValue)
        _year = State(initialValue: comps.year ?? cal.component(.year, from: .now))
        _month = State(initialValue: comps.month ?? cal.component(.month, from: .now))
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
                    selected = newDate          // ← 年月を反映
                }
                dismiss()                        // ← そのまま閉じる
            } label: {
                Text("決定")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
