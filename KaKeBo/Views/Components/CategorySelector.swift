//
//  Views/Components/CategorySelector.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct CategorySelector: View {
    @EnvironmentObject var store: DataStore
    @Binding var selectedCategoryId: UUID?
    @Environment(\.horizontalSizeClass) private var hSize
    
    /// ＋ボタンのタップ時に呼ばれる（nilなら表示しない）
    var onTapAdd: (() -> Void)? = nil
    /// ＋カードを表示するか（デフォルト true）
    var showsAddButton: Bool = true
    
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
                        .font(.callout).foregroundStyle(.secondary)
                    if let onTapAdd, showsAddButton {
                        Button(action: onTapAdd) {
                            CategoryCard(
                                name: "カテゴリーを追加",
                                symbolName: "plus.circle.fill",
                                color: .accentColor,
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
                        Button(action: onTapAdd) {
                            CategoryCard(
                                name: "カテゴリー追加",
                                symbolName: "plus.circle.fill",
                                color: .accentColor,
                                isSelected: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("カテゴリー追加")
                    }
                }
            }
        }
        .luxCard()
    }
}
