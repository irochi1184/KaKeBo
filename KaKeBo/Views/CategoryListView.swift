//
//  Views/CategoryListView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import CloudKit

// どの家計簿のカテゴリを見ているか
private enum CategoryOwner: Hashable {
    case personal
    case shared(CKRecord.ID)
}

struct CategoryListView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var purchase: PurchaseManager

    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext

    @Environment(\.dismiss) private var dismiss
    
    @Environment(\.colorScheme) private var scheme
    
    @State private var showAdd = false
    @State private var showPaywall = false
    
    // 個人用カテゴリ削除確認
    @State private var pendingDeleteIDs: [UUID] = []
    @State private var showDeleteConfirm = false
    
    // 共有カテゴリ削除確認
    @State private var pendingSharedDeleteIDs: [CKRecord.ID] = []
    @State private var showSharedDeleteConfirm = false
    
    // クイック追加の折りたたみ
    @State private var showQuickAdd = true
    @State private var isCreatingSharedCategory = false
    
    // 対象家計簿（個人 or 共有）
    @State private var owner: CategoryOwner = .personal
    
    private let freeCategoryLimit = 12
    
    // 個人用の制限（共有側は制限なしにしている）
    private var personalAtLimit: Bool {
        !purchase.isPremiumActive && store.categories.count >= freeCategoryLimit
    }
    
    private var sharedAtLimit: Bool {
        guard let ledger = currentSharedLedger else { return false }
        let cats = sharedLedgerStore.categoriesByLedger[ledger.id] ?? []
        return !purchase.isPremiumActive && cats.count >= freeCategoryLimit
    }
    
    /// 今見ているのが個人用かどうか
    private var isPersonalScope: Bool {
        if case .personal = owner { return true } else { return false }
    }
    
    /// 今見ている共有家計簿（なければ nil）
    private var currentSharedLedger: SharedLedger? {
        guard case .shared(let id) = owner else { return nil }
        return sharedLedgerStore.ledgers.first(where: { $0.id == id })
    }
    
    /// 今見ている共有家計簿のカテゴリ一覧
    private var currentSharedCategories: [SharedCategory] {
        guard let ledger = currentSharedLedger else { return [] }
        return sharedLedgerStore.categoriesByLedger[ledger.id] ?? []
    }
    
    var body: some View {
        NavigationStack {
            List {
                // MARK: 対象家計簿ピッカー
                Section {
                    ownerPicker
                } header: {
                    Text("カテゴリ対象")
                }
                
                // MARK: 個人用カテゴリ
                if isPersonalScope {
                    personalQuickAddSection
                    personalCategorySection
                }
                // MARK: 共有用カテゴリ
                else {
                    sharedQuickAddSection
                    sharedCategorySection
                }
            }
            .navigationTitle("カテゴリ")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .disabled(!isPersonalScope && currentSharedLedger == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if isPersonalScope {
                            if personalAtLimit {
                                showPaywall = true
                            } else {
                                showAdd = true
                            }
                        } else {
                            if sharedAtLimit {
                                showPaywall = true
                            } else {
                                showAdd = true
                            }
                        }
                    } label: { Image(systemName: "plus") }
                }
            }
            
            // 個人用削除確認
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
            
            // 共有用削除確認
            .confirmationDialog(
                "共有カテゴリの削除",
                isPresented: $showSharedDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let ledger = currentSharedLedger {
                        Task {
                            for id in pendingSharedDeleteIDs {
                                await sharedLedgerStore.deleteCategory(id, from: ledger)
                            }
                            pendingSharedDeleteIDs.removeAll()
                            await sharedLedgerStore.reloadCategories(for: ledger)
                        }
                    } else {
                        pendingSharedDeleteIDs.removeAll()
                    }
                }
                Button("キャンセル", role: .cancel) {
                    pendingSharedDeleteIDs.removeAll()
                }
            } message: {
                Text("選択した共有カテゴリを削除します。よろしいですか？")
            }
            
            // 新規追加シート
            .sheet(isPresented: $showAdd) {
                if isPersonalScope {
                    CategoryEditorView(category: (nil as Category?))
                        .environmentObject(store)
                        .environmentObject(themeStore)
                        .environmentObject(purchase)
                } else if let ledger = currentSharedLedger {
                    SharedCategoryEditorView(ledger: ledger, category: nil)
                        .environmentObject(sharedLedgerStore)
                        .environmentObject(themeStore)
                }
            }
            
            // 課金シート
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .task {
            // 共有家計簿とカテゴリを一応最新に
            await sharedLedgerStore.reloadLedgers()
            if let ledger = currentSharedLedger {
                await sharedLedgerStore.reloadCategories(for: ledger)
            }
        }
        .onAppear {
            // 初回は HomeView の選択状態に合わせる
            if ledgerContext.isShared,
               let shared = ledgerContext.currentSharedLedger(from: sharedLedgerStore) {
                owner = .shared(shared.id)
            } else {
                owner = .personal
            }
        }
        .onChange(of: owner) { _, newValue in
            // 共有家計簿を切り替えたらカテゴリを再ロード
            if case .shared(let id) = newValue,
               let ledger = sharedLedgerStore.ledgers.first(where: { $0.id == id }) {
                Task { await sharedLedgerStore.reloadCategories(for: ledger) }
            }
        }
    }
    
    private var ownerPicker: some View {
        Picker("対象家計簿", selection: $owner) {
            Text("個人用").tag(CategoryOwner.personal)
            
            ForEach(sharedLedgerStore.ledgers) { ledger in
                // 明示的に tag の型を分かりやすくする
                let tag: CategoryOwner = .shared(ledger.id)
                Text("共有: \(ledger.name)")
                    .tag(tag)
            }
        }
        .pickerStyle(.menu)
    }

}

// MARK: - 個人用セクション

private extension CategoryListView {
    var personalQuickAddSection: some View {
        Section {
            QuickAddGrid(
                presets: PresetCategory.all.filter { p in
                    store.categories.contains(where: { $0.name == p.name }) == false
                },
                onTap: { p in
                    if personalAtLimit {
                        showPaywall = true
                    } else {
                        let cat = Category(name: p.name, symbolName: p.symbol, color: p.color)
                        store.addCategory(cat)
                    }
                },
                isLocked: personalAtLimit
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            
            if personalAtLimit {
                Text("無料プランではカテゴリは \(freeCategoryLimit) 件までです。\nプレミアムプラン加入で上限無制限になります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
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
    
    var personalCategorySection: some View {
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
                pendingDeleteIDs = idx.map { store.categories[$0].id }
                showDeleteConfirm = true
            }
            .onMove(perform: store.moveCategories)
        }
    }
}

// MARK: - 共有用セクション

private extension CategoryListView {
    
    // MARK: 共有用クイック追加
    var sharedQuickAddSection: some View {
        Section {
            if let ledger = currentSharedLedger {
                QuickAddGrid(
                    presets: PresetCategory.all.filter { p in
                        // 共有カテゴリ側にまだないプリセットだけ出す
                        currentSharedCategories.contains(where: { $0.name == p.name }) == false
                    },
                    onTap: { p in
                        // 上限チェック
                        if sharedAtLimit {
                            showPaywall = true
                            return
                        }
                        // 連打防止
                        if isCreatingSharedCategory { return }
                        
                        isCreatingSharedCategory = true

                        Task {
                            _ = await sharedLedgerStore.createCategory(
                                for: ledger,
                                name: p.name,
                                colorHex: p.color.toHexString(),
                                icon: p.symbol
                            )
                            await sharedLedgerStore.reloadCategories(for: ledger)
                            await MainActor.run {
                                isCreatingSharedCategory = false
                            }
                        }
                    },
                    // 上限 or 作成中はロック見た目
                    isLocked: sharedAtLimit || isCreatingSharedCategory
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                
                if sharedAtLimit {
                    Text("無料プランではカテゴリは \(freeCategoryLimit) 件までです。\nプレミアムプラン加入で上限無制限になります。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 6)
                }
            } else {
                Text("共有家計簿が選択されていません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("共有カテゴリのクイック追加")
        }
    }

    
    var sharedCategorySection: some View {
        Section {
            if let ledger = currentSharedLedger {
                ForEach(currentSharedCategories, id: \.id) { cat in
                    NavigationLink {
                        SharedCategoryEditorView(ledger: ledger, category: cat)
                            .environmentObject(sharedLedgerStore)
                            .environmentObject(themeStore)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: cat.icon)
                                .foregroundStyle(Color.fromHex(cat.colorHex) ?? .blue)
                                .frame(width: 28)
                            Text(cat.name)
                        }
                    }
                }
                .onDelete { idx in
                    pendingSharedDeleteIDs = idx.map { currentSharedCategories[$0].id }
                    showSharedDeleteConfirm = true
                }
            } else {
                Text("共有家計簿を選択するとカテゴリを編集できます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// ========== 個人カテゴリ編集画面 ==========
struct CategoryEditorView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    
    @State private var name: String = ""
    @State private var symbolName: String = "tag.fill"
    @State private var color: Color = .blue
    
    private var editingId: UUID? = nil
    
    private let freeCategoryLimit = 12
    @EnvironmentObject var purchase: PurchaseManager
    @State private var showPaywall = false
    
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
            .sheet(isPresented: $showPaywall) {
                PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                    .presentationDetents([.large, .medium])
                    .presentationDragIndicator(.visible)
            }
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
        
        // 新規時のみ課金ガード
        if editingId == nil {
            let isOverLimit = !purchase.isPremiumActive && store.categories.count >= freeCategoryLimit
            if isOverLimit {
                showPaywall = true
                return
            }
        }
        
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

// ========== 共有カテゴリ編集画面 ==========
struct SharedCategoryEditorView: View {
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    
    let ledger: SharedLedger
    let editingCategory: SharedCategory?
    
    /// 保存完了時に呼び出されるコールバック（新しく保存されたカテゴリを返す）
    var onSaved: ((SharedCategory) -> Void)?
    
    @State private var name: String = ""
    @State private var icon: String = "tag.fill"
    @State private var colorHex: String = "#FF9500"
    @State private var color: Color = .orange
    
    // MARK: - init
    
    init(
        ledger: SharedLedger,
        category: SharedCategory? = nil,
        onSaved: ((SharedCategory) -> Void)? = nil
    ) {
        self.ledger = ledger
        self.editingCategory = category
        self.onSaved = onSaved
        
        if let c = category {
            _name = State(initialValue: c.name)
            _icon = State(initialValue: c.icon)
            _colorHex = State(initialValue: c.colorHex)
            _color = State(initialValue: Color.fromHex(c.colorHex) ?? .orange)
        }
    }
    
    private var isEditing: Bool { editingCategory != nil }
    private var isEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名前（例：食費）", text: $name)
                    
                    ColorPicker("色", selection: $color, supportsOpacity: false)
                        .onChange(of: color) { _, newValue in
                            colorHex = newValue.toHexString()
                        }
                    
                    NavigationLink {
                        SymbolPickerView(selected: $icon)
                            .navigationTitle("シンボルを選択")
                    } label: {
                        HStack {
                            Text("アイコン")
                            Spacer()
                            Image(systemName: icon)
                                .foregroundStyle(color)
                        }
                    }
                }
                .listRowBackground(
                    scheme == .dark
                    ? Color.white.opacity(0.06)
                    : Color.black.opacity(0.02)
                )
                
                Section("プレビュー") {
                    HStack(spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(color.opacity(0.12))
                            Image(systemName: icon)
                                .foregroundStyle(color)
                        }
                        .frame(width: 36, height: 36)
                        
                        Text(name.isEmpty ? "未入力" : name)
                            .font(.subheadline.weight(.medium))
                        
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(
                    scheme == .dark
                    ? Color.white.opacity(0.06)
                    : Color.black.opacity(0.02)
                )
            }
            .scrollContentBackground(.hidden)
            .background(themeStore.theme.backgroundColor(for: scheme))
            .navigationTitle(isEditing ? "共有カテゴリ編集" : "共有カテゴリ追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            SaveButton(
                isEnabled: isEnabled,
                accent: themeStore.theme.accentColor(for: scheme)
            ) {
                Task { await save() }
            }
        }
    }
    
    // MARK: - 保存処理
    
    private func save() async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if let editingCategory {
            // 既存カテゴリの更新
            if let updated = await sharedLedgerStore.updateCategory(
                editingCategory,
                in: ledger,
                name: trimmed,
                colorHex: colorHex,
                icon: icon
            ) {
                onSaved?(updated)
            }
        } else {
            // 新規作成
            if let created = await sharedLedgerStore.createCategory(
                for: ledger,
                name: trimmed,
                colorHex: colorHex,
                icon: icon
            ) {
                onSaved?(created)
            }
        }
        
        await sharedLedgerStore.reloadCategories(for: ledger)
        dismiss()
    }
}


private let presetHexByName: [String: String] = [
    "食費":       "#F28B59",
    "通信料":     "#BFA5FF",
    "交際費":     "#00DAC3",
    "その他収入": "#3BD3FE",
    "水道光熱費": "#92E2E6",
    "交通費":     "#91ACBE",
    "住宅費":     "#6199CF",
    "医療費":     "#BB74A3",
    "娯楽費":     "#77B98A",
    "給与":       "#509C9C",
    "日用品費":   "#FFD88F",
]

struct PresetCategory {
    let name: String
    let symbol: String
    let color: Color
    
    /// 名前に一致するHEX色があればそれを、無ければフォールバック色を返す
    private static func color(for name: String, fallback: Color) -> Color {
        if let hex = presetHexByName[name], let c = Color.fromHex(hex) {
            return c
        }
        print("⚠️ Fallback color used for:", name)
        return fallback
    }
    
    static let all: [PresetCategory] = [
        .init(name: "食費",       symbol: "fork.knife",
              color: color(for: "食費",       fallback: .red)),
        
            .init(name: "日用品費",   symbol: "bag.fill",
                  color: color(for: "日用品費",   fallback: .orange)),
        
            .init(name: "水道光熱費", symbol: "lightbulb.fill",
                  color: color(for: "水道光熱費", fallback: .blue)),
        
            .init(name: "交通費",     symbol: "tram.fill",
                  color: color(for: "交通費",     fallback: .teal)),
        
            .init(name: "通信料",     symbol: "wifi",
                  color: color(for: "通信料",     fallback: .indigo)),
        
            .init(name: "住宅費",     symbol: "house.fill",
                  color: color(for: "住宅費",     fallback: .brown)),
        
            .init(name: "医療費",     symbol: "cross.case.fill",
                  color: color(for: "医療費",     fallback: .pink)),
        
            .init(name: "被服費",     symbol: "tshirt.fill",
                  color: .purple),
        
            .init(name: "交際費",     symbol: "gift.fill",
                  color: color(for: "交際費",     fallback: .mint)),
        
            .init(name: "娯楽費",     symbol: "gamecontroller.fill",
                  color: color(for: "娯楽費",     fallback: .green)),
        
            .init(name: "美容費",     symbol: "scissors",
                  color: .pink),
        
            .init(name: "子ども費",   symbol: "figure.2.and.child.holdinghands",
                  color: .cyan),
        
            .init(name: "雑費",       symbol: "ellipsis.circle.fill",
                  color: .gray),
        
            .init(name: "特別費",     symbol: "sparkles",
                  color: .yellow),
        
            .init(name: "保険料",     symbol: "shield.checkerboard",
                  color: .blue),
        
            .init(name: "車両費",     symbol: "car.fill",
                  color: .orange),
        
            .init(name: "学費",       symbol: "book.fill",
                  color: .brown),
        
            .init(name: "税金",       symbol: "yensign.circle",
                  color: .red),
        
            .init(name: "習い事",     symbol: "music.note.list",
                  color: .purple),
        
            .init(name: "小遣い",     symbol: "banknote.fill",
                  color: .green),
        
        // 収入系
        .init(name: "給与",       symbol: "banknote", // ←必要なら "yensign.circle" に合わせてもOK
              color: color(for: "給与",       fallback: .green)),
        
            .init(name: "その他収入", symbol: "yensign.circle.fill",
                  color: color(for: "その他収入", fallback: .cyan)),
    ]
}


private struct QuickAddGrid: View {
    let presets: [PresetCategory]
    let onTap: (PresetCategory) -> Void
    var isLocked: Bool = false
    
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
                        .overlay(alignment: .topTrailing) {
                            if isLocked {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .padding(4)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .opacity(isLocked ? 0.65 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

