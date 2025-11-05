//
//  Views/Security/PasscodeLengthPickerView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import SwiftUI

struct PasscodeLengthPickerView: View {
    let initial: Int
    let onCancel: () -> Void
    let onSelect: (Int) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var length: Int
    
    init(initial: Int, onCancel: @escaping () -> Void, onSelect: @escaping (Int) -> Void) {
        self.initial = (4...10).contains(initial) ? initial : 6
        self.onCancel = onCancel
        self.onSelect = onSelect
        _length = State(initialValue: self.initial)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(footer: Text("4〜10桁から選択してください。")) {
                    Picker("パスコード桁数", selection: $length) {
                        ForEach(4...10, id: \.self) { n in
                            Text("\(n)桁").tag(n)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxHeight: 160)
                }
            }
            .navigationTitle("パスコード桁数")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("決定") {
                        onSelect(length)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
