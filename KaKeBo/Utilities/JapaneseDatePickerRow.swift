//
//  Utilities/JapaneseDatePickerRow.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/22.
//

import SwiftUI

struct JapaneseDatePickerRow: View {
    @Binding var date: Date
    @State private var showPicker = false
    
    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("日付")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Button {
                showPicker = true
            } label: {
                HStack {
                    Text(dateText)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.thinMaterial)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPicker) {
                NavigationStack {
                    VStack {
                        DatePicker(
                            "日付を選択",
                            selection: $date,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.wheel)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                        .labelsHidden()
                        .padding()
                        Spacer()
                    }
                    .navigationTitle("日付を選択")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完了") { showPicker = false }
                        }
                    }
                }
                .presentationDetents([.height(350), .medium])
            }
        }
    }
}
