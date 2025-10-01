//
//  Views/RecurringTodoSettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/02.
//

import SwiftUI

struct RecurringTodoSettingsView: View {
    @AppStorage("kakebo.recurring.templates") private var templatesData: Data = Data()
    
    @State private var templates: [RecurringTodoTemplate] = []
    @State private var newTitle: String = ""
    @State private var newDay: Int = 0   // 0=月末, 1...31
    
    var body: some View {
        Form {
            Section("新規追加") {
                HStack(spacing: 10) {
                    TextField("例：家賃の支払い", text: $newTitle)
                        .textInputAutocapitalization(.never)
                    
                    Picker("日付", selection: $newDay) {
                        Text("月末").tag(0)
                        ForEach(1...31, id: \.self) { d in Text("\(d)日").tag(d) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 68)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.thinMaterial))
                    
                    Button {
                        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !title.isEmpty else { return }
                        templates.append(.init(title: title, dayOfMonth: newDay, isActive: true))
                        newTitle = ""; newDay = 0
                        save()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            
            Section("登録済み") {
                if templates.isEmpty {
                    Text("まだ登録がありません").foregroundStyle(.secondary)
                } else {
                    ForEach(templates) { tpl in
                        let binding = Binding<RecurringTodoTemplate>(
                            get: { templates.first(where: { $0.id == tpl.id }) ?? tpl },
                            set: { newVal in
                                if let i = templates.firstIndex(where: { $0.id == tpl.id }) {
                                    templates[i] = newVal
                                    save()
                                }
                            }
                        )
                        HStack {
                            Toggle(isOn: binding.isActive) { EmptyView() }
                                .labelsHidden()
                            
                            TextField("タイトル", text: binding.title)
                                .textInputAutocapitalization(.never)
                            
                            Picker("日付", selection: binding.dayOfMonth) {
                                Text("月末").tag(0)
                                ForEach(1...31, id: \.self) { d in Text("\(d)日").tag(d) }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(minWidth: 68)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.thinMaterial))
                        }
                    }
                    .onDelete { indexSet in
                        let ids = indexSet.map { templates[$0].id }
                        templates.removeAll { ids.contains($0.id) }
                        save()
                    }
                }
            }
        }
        .onAppear(perform: load)
    }
    
    private func load() {
        if templatesData.isEmpty {
            templates = []
        } else if let items = try? JSONDecoder().decode([RecurringTodoTemplate].self, from: templatesData) {
            templates = items
        }
    }
    private func save() {
        templatesData = (try? JSONEncoder().encode(templates)) ?? Data()
    }
}
