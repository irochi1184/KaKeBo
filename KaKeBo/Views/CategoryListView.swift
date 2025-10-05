//
//  Views/CategoryListView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct CategoryListView: View {
    @EnvironmentObject var store: DataStore
    @State private var showAdd = false
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(store.categories) { cat in
                    // まずは古典的 NavigationLink で確実に遷移
                    NavigationLink {
                        CategoryEditorView(category: cat)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: cat.symbolName)
                                .foregroundStyle(cat.color)
                                .frame(width: 28)
                            Text(cat.name)
                        }
                    }
                }
                .onDelete { idx in
                    idx.map { store.categories[$0] }.forEach(store.deleteCategory)
                }
            }
            .navigationTitle("カテゴリ")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAdd) {
                // nil の型推論を助けるために Category? を明示
                CategoryEditorView(category: (nil as Category?))
                    .environmentObject(store)
            }
        }
    }
}

// ========== 編集画面（同ファイルに定義してスコープ問題を潰す） ==========
struct CategoryEditorView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var symbolName: String = "tag.fill"
    @State private var color: Color = .blue
    private var editingId: UUID? = nil
    
    // Category? を受け取り、State を初期化
    init(category: Category?) {
        if let c = category {
            _name = State(initialValue: c.name)
            _symbolName = State(initialValue: c.symbolName)
            _color = State(initialValue: c.color)
            editingId = c.id
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("名前", text: $name)
                ColorPicker("色", selection: $color, supportsOpacity: false)
                
                NavigationLink {
                    SymbolPickerView(selected: $symbolName)
                        .navigationTitle("シンボルを選択")
                } label: {
                    HStack {
                        Text("アイコン")
                        Spacer()
                        Image(systemName: symbolName).foregroundStyle(color)
                    }
                }
            }
            .navigationTitle(editingId == nil ? "カテゴリ追加" : "カテゴリ編集")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        let cat = Category(
                            id: editingId ?? UUID(),
                            name: name,
                            symbolName: symbolName,
                            color: color
                        )
                        if editingId == nil {
                            store.addCategory(cat)
                        } else {
                            store.updateCategory(cat)
                        }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
