//
//  Views/Settings/FixedExpenseEditorView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/18.
//

import SwiftUI

struct FixedExpenseEditorView: View {
    let initial: FixedExpenseTemplate?
    let categories: [Category]
    let onSave: (FixedExpenseTemplate) -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var title: String = ""
    @State private var amount: Int = 0
    @State private var dayOfMonth: Int = 0   // 0=月末
    @State private var categoryId: UUID? = nil
    @State private var memo: String = ""
    @State private var isActive: Bool = true
    
    init(initial: FixedExpenseTemplate?, categories: [Category], onSave: @escaping (FixedExpenseTemplate) -> Void) {
        self.initial = initial
        self.categories = categories
        self.onSave = onSave
        if let t = initial {
            _title = State(initialValue: t.title)
            _amount = State(initialValue: t.amount)
            _dayOfMonth = State(initialValue: t.dayOfMonth)
            _categoryId = State(initialValue: t.categoryId)
            _memo = State(initialValue: t.memo ?? "")
            _isActive = State(initialValue: t.isActive)
        } else {
            _categoryId = State(initialValue: categories.first?.id)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称（例：家賃）", text: $title)
                    amountField
                    dayPicker
                    categoryPicker
                    TextField("メモ（任意）", text: $memo)
                }
                Section {
                    Toggle("有効にする", isOn: $isActive)
                }
            }
            .navigationTitle(initial == nil ? "固定費を追加" : "固定費を編集")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        if let t = currentTemplate() {
                            onSave(t)
                            dismiss()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
    
    private var amountField: some View {
        HStack {
            Text("金額")
            Spacer()
            TextField("0", value: $amount, formatter: intFormatter)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 120)
        }
    }
    
    private var dayPicker: some View {
        HStack {
            Text("日付")
            Spacer()
            Picker("", selection: $dayOfMonth) {
                Text("月末").tag(0)
                ForEach(1...31, id: \.self) { d in
                    Text("\(d)日").tag(d)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var categoryPicker: some View {
        HStack {
            Text("カテゴリ")
            Spacer()
            Picker("", selection: Binding(
                get: { categoryId ?? categories.first?.id ?? UUID() },
                set: { categoryId = $0 }
            )) {
                ForEach(categories) { c in
                    HStack {
                        Image(systemName: c.symbolName).foregroundStyle(c.color)
                        Text(c.name)
                    }
                    .tag(c.id)
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    private var intFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .none
        return f
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount > 0 && categoryId != nil
    }
    
    private func currentTemplate() -> FixedExpenseTemplate? {
        guard let cat = categoryId else { return nil }
        return FixedExpenseTemplate(
            id: initial?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            dayOfMonth: dayOfMonth,
            categoryId: cat,
            memo: memo.isEmpty ? nil : memo,
            isActive: isActive
        )
    }
}
