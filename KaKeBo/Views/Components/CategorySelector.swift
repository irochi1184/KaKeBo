//
//  Views/Components/CategorySelector.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import CloudKit

// MARK: - 個人用家計簿のカテゴリ
struct CategorySelector: View {
    @EnvironmentObject var store: DataStore
    @Binding var selectedCategoryId: UUID?
    @Environment(\.horizontalSizeClass) private var hSize
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @EnvironmentObject var purchase: PurchaseManager
    @State private var showPaywall = false
    
    /// ＋ボタンのタップ時に呼ばれる（nilなら表示しない）
    var onTapAdd: (() -> Void)? = nil
    /// ＋カードを表示するか（デフォルト true）
    var showsAddButton: Bool = true
    
    // 課金ガード（個人用カテゴリ）
    private let freeCategoryLimit = 12
    private var atLimit: Bool {
        !purchase.isPremiumActive && store.categories.count >= freeCategoryLimit
    }
    
    // iPhoneコンパクト幅：4列 / それ以外：6列
    private var columns: [GridItem] {
        let count = (hSize == .compact) ? 4 : 6
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            if store.categories.isEmpty {
                // 空のときはメッセージ＋「追加カード」だけ並べる
                VStack(alignment: .leading, spacing: 10) {
                    Text("カテゴリがありません。先に追加してください。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let onTapAdd, showsAddButton {
                        Button(action: onTapAdd) {
                            CategoryCard(
                                name: "カテゴリーを追加",
                                symbolName: "plus.circle.fill",
                                color: themeStore.theme.accentColor(for: scheme),
                                isSelected: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("カテゴリーを追加")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    // 既存カテゴリ
                    ForEach(store.categories, id: \.id) { cat in
                        let isSelected = (selectedCategoryId == cat.id)
                        Button {
                            selectedCategoryId = cat.id
                        } label: {
                            CategoryCard(
                                name: cat.name,
                                symbolName: cat.symbolName,
                                color: cat.color,
                                isSelected: isSelected
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(cat.name)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                    // 最後尾に「＋ 追加」カードを差し込む（onTapAdd があるときのみ）
                    if let onTapAdd, showsAddButton {
                        Button {
                            handleAddTapped(onTapAdd)
                        } label: {
                            CategoryCard(
                                name: "カテゴリー追加",
                                symbolName: "plus.circle.fill",
                                color: .accentColor,
                                isSelected: false
                            )
                            .opacity(atLimit ? 0.6 : 1)
                            .overlay(alignment: .topTrailing) {
                                if atLimit {
                                    Image(systemName: "lock.fill")
                                        .font(.caption2)
                                        .padding(6)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("カテゴリー追加")
                    }
                }
            }
        }
        .luxCard()
        .onAppear {
            // ★ 初期選択：何も選ばれていなければ先頭カテゴリを選択
            if selectedCategoryId == nil, let first = store.categories.first {
                selectedCategoryId = first.id
            }
        }
        // 課金シート
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    private func handleAddTapped(_ onTapAdd: () -> Void) {
        if atLimit {
            showPaywall = true
        } else {
            onTapAdd()
        }
    }
}

// MARK: - 共有用家計簿のカテゴリ
struct SharedCategorySelector: View {
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var purchase: PurchaseManager
    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var hSize
    @State private var showPaywall = false
    
    /// 共有カテゴリの選択ID（CKRecord.ID）
    @Binding var selectedCategoryId: CKRecord.ID?
    
    /// ＋ボタンタップ時（nilなら非表示）
    var onTapAdd: (() -> Void)? = nil
    var showsAddButton: Bool = true
    
    // 共通のカテゴリ上限
    private let freeCategoryLimit = 12
    private func atLimit(for ledger: SharedLedger) -> Bool {
        let count = sharedLedgerStore
            .categoriesByLedger[ledger.id]?
            .count ?? 0
        
        return !purchase.isPremiumActive && count >= freeCategoryLimit
    }

    
    // レイアウト（iPhone：4列 / それ以外：6列）
    private var columns: [GridItem] {
        let count = (hSize == .compact) ? 4 : 6
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }
    
    /// 指定レジャーの「共有カテゴリ」が無料上限を超えているかどうか
    private func isOverLimit(for ledger: SharedLedger) -> Bool {
        let count = sharedLedgerStore.categoriesByLedger[ledger.id]?.count ?? 0
        return !purchase.isPremiumActive && count >= freeCategoryLimit
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            if let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore) {
                let cats = sharedLedgerStore.categoriesByLedger[ledger.id] ?? []
                
                if cats.isEmpty {
                    // カテゴリがまだ無いとき
                    VStack(alignment: .leading, spacing: 10) {
                        Text("この共有家計簿にはまだカテゴリがありません。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        
                        if let onTapAdd, showsAddButton {
                            Button {
                                // 上限チェック → 課金 or 追加
                                if isOverLimit(for: ledger) {
                                    showPaywall = true
                                } else {
                                    onTapAdd()
                                }
                            } label: {
                                CategoryCard(
                                    name: "カテゴリーを追加",
                                    symbolName: "plus.circle.fill",
                                    color: themeStore.theme.accentColor(for: scheme),
                                    isSelected: false
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("カテゴリーを追加")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        // 共有カテゴリ一覧
                        ForEach(cats, id: \.id) { cat in
                            let isSelected = (selectedCategoryId == cat.id)
                            Button {
                                selectedCategoryId = cat.id
                            } label: {
                                CategoryCard(
                                    name: cat.name,
                                    symbolName: cat.icon, // SharedCategory.icon
                                    color: Color.fromHex(cat.colorHex)
                                    ?? themeStore.theme.accentColor(for: scheme),
                                    isSelected: isSelected
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(cat.name)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                        
                        // 共有カテゴリの追加ボタン（必要なら）
                        if let onTapAdd, showsAddButton {
                            Button {
                                if isOverLimit(for: ledger) {
                                    showPaywall = true
                                } else {
                                    onTapAdd()
                                }
                            } label: {
                                CategoryCard(
                                    name: "カテゴリー追加",
                                    symbolName: "plus.circle.fill",
                                    color: .accentColor,
                                    isSelected: false
                                )
                                .opacity(atLimit(for:ledger) ? 0.6 : 1)
                                .overlay(alignment: .topTrailing) {
                                    if atLimit(for:ledger) {
                                        Image(systemName: "lock.fill")
                                            .font(.caption2)
                                            .padding(6)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("カテゴリー追加")
                        }
                    }
                }
            } else {
                // 共有レジャー未選択時
                VStack(alignment: .leading, spacing: 8) {
                    Text("共有家計簿が選択されていません。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("ホーム画面左上から共有家計簿を選択してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .luxCard()
        .onAppear {
            // ★ 初期選択：共有カテゴリがあれば先頭を選択
            if selectedCategoryId == nil,
               let ledger = ledgerContext.currentSharedLedger(from: sharedLedgerStore),
               let first = (sharedLedgerStore.categoriesByLedger[ledger.id] ?? []).first {
                selectedCategoryId = first.id
            }
        }
        // 課金シート
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
    }
}
