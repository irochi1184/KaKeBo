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
    
    // 削除確認のための状態
    @State private var pendingDeleteIDs: [UUID] = []
    @State private var showDeleteConfirm = false
    
    // クイック追加の折りたたみ
    @State private var showQuickAdd = true
    
    var body: some View {
        NavigationStack {
            List {
                // クイック追加セクション
                if showQuickAdd {
                    Section {
                        QuickAddGrid(
                            // まだ存在しないプリセットだけ出す（名前で比較）
                            presets: PresetCategory.all.filter { p in
                                store.categories.contains(where: { $0.name == p.name }) == false
                            },
                            onTap: { p in
                                let cat = Category(name: p.name, symbolName: p.symbol, color: p.color)
                                store.addCategory(cat)
                            }
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    } header: {
                        HStack {
                            Text("クイック追加")
                            Spacer()
                            Button(showQuickAdd ? "隠す" : "表示") {
                                withAnimation(.snappy) { showQuickAdd.toggle() }
                            }
                            .font(.caption)
                        }
                    }
                }
                
                // 通常リスト
                Section {
                    ForEach(store.categories) { cat in
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
                        // 削除要求を一旦保存して確認ダイアログ
                        pendingDeleteIDs = idx.map { store.categories[$0].id }
                        showDeleteConfirm = true
                    }
                    .onMove(perform: store.moveCategories) // ← 並べ替え
                }
            }
            .navigationTitle("カテゴリ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton() // ← これで並べ替え＆複数削除モード
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAdd = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .confirmationDialog(
                "削除の確認",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("削除（家計簿データも削除）", role: .destructive) {
                    store.deleteCategories(with: pendingDeleteIDs)
                    pendingDeleteIDs.removeAll()
                }
                Button("キャンセル", role: .cancel) {
                    pendingDeleteIDs.removeAll()
                }
            } message: {
                Text("選択したカテゴリに紐づく家計簿の記録もすべて削除されます。よろしいですか？")
            }
            .sheet(isPresented: $showAdd) {
                CategoryEditorView(category: (nil as Category?))
                    .environmentObject(store)
            }
        }
    }
}

// ========== 編集画面（同ファイルに定義してスコープ問題を潰す） ==========
struct CategoryEditorView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var symbolName: String = "tag.fill"
    @State private var color: Color = .blue
    
    private var editingId: UUID? = nil
    var onSaved: ((Category) -> Void)? = nil
    
    init(category: Category?, onSaved: ((Category) -> Void)? = nil) {
        self.onSaved = onSaved
        if let c = category {
            _name = State(initialValue: c.name)
            _symbolName = State(initialValue: c.symbolName)
            _color = State(initialValue: c.color)
            editingId = c.id
        }
    }
    
    private var isEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名前（例：食費）", text: $name)
                    ColorPicker("色", selection: $color, supportsOpacity: false)
                    
                    NavigationLink {
                        SymbolPickerView(selected: $symbolName)
                            .navigationTitle("シンボルを選択")
                    } label: {
                        HStack {
                            Text("アイコン")
                            Spacer()
                            Image(systemName: symbolName)
                                .foregroundStyle(color)
                        }
                    }
                }
                .listRowBackground(scheme == .dark ? Color.white.opacity(0.06) : .black.opacity(0.02))
                
                // ちょいプレビュー
                Section("プレビュー") {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(color.opacity(0.12))
                            Image(systemName: symbolName)
                                .foregroundStyle(color)
                        }
                        .frame(width: 36, height: 36)
                        Text(name.isEmpty ? "未入力" : name)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(scheme == .dark ? Color.white.opacity(0.06) : .black.opacity(0.02))
            }
            .scrollContentBackground(.hidden)
            .background(themeStore.theme.backgroundColor(for: scheme))
            .navigationTitle(editingId == nil ? "カテゴリ追加" : "カテゴリ編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if editingId == nil {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") { dismiss() }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            SaveButton(
                isEnabled: isEnabled,
                accent: themeStore.theme.accentColor(for: scheme)
            ) { save() }
        }
    }
    
    // MARK: - Actions
    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let cat = Category(
            id: editingId ?? UUID(),
            name: trimmed,
            symbolName: symbolName,
            color: color
        )
        if editingId == nil {
            store.addCategory(cat)
        } else {
            store.updateCategory(cat)
        }
        onSaved?(cat)
        dismiss()
    }
}

// 同ファイル末尾 or 別ファイルでもOK

struct PresetCategory {
    let name: String
    let symbol: String
    let color: Color
    
    static let all: [PresetCategory] = [
        .init(name: "食費",       symbol: "fork.knife",              color: .red),
        .init(name: "日用品費",   symbol: "bag.fill",                color: .orange),
        .init(name: "水道光熱費", symbol: "lightbulb.fill",          color: .blue),
        .init(name: "交通費",     symbol: "tram.fill",               color: .teal),
        .init(name: "通信料",     symbol: "wifi",                    color: .indigo),
        .init(name: "住宅費",     symbol: "house.fill",              color: .brown),
        .init(name: "医療費",     symbol: "cross.case.fill",         color: .pink),
        .init(name: "被服費",     symbol: "tshirt.fill",             color: .purple),
        .init(name: "交際費",     symbol: "gift.fill",               color: .mint),
        .init(name: "娯楽費",     symbol: "gamecontroller.fill",     color: .green),
        .init(name: "美容費",     symbol: "scissors",                color: .pink),
        .init(name: "子ども費",   symbol: "figure.2.and.child.holdinghands", color: .cyan),
        .init(name: "雑費",       symbol: "ellipsis.circle.fill",    color: .gray),
        .init(name: "特別費",     symbol: "sparkles",                color: .yellow),
        .init(name: "保険料",     symbol: "shield.checkerboard",     color: .blue),
        .init(name: "車両費",     symbol: "car.fill",                color: .orange),
        .init(name: "学費",       symbol: "book.fill",               color: .brown),
        .init(name: "税金",       symbol: "yensign.circle",          color: .red),
        .init(name: "習い事",     symbol: "music.note.list",         color: .purple),
        .init(name: "小遣い",     symbol: "banknote.fill", color: .green),
        
        // 収入系（必要ならここからも追加できる）
        .init(name: "給与",       symbol: "banknote",                color: .green),
        .init(name: "その他収入", symbol: "yensign.circle.fill",     color: .cyan),
    ]
}

private struct QuickAddGrid: View {
    let presets: [PresetCategory]
    let onTap: (PresetCategory) -> Void
    
    // 横スクロールのチップ群（件数が多いのでスクロール式が扱いやすい）
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(presets, id: \.name) { p in
                    Button {
                        onTap(p)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: p.symbol).foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(p.color.gradient))
                            Text(p.name)
                                .font(.caption)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(p.color.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
