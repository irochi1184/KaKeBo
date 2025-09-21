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
    
    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリ")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            if store.categories.isEmpty {
                Text("カテゴリがありません。先に追加してください。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
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
                }
            }
        }
        .luxCard()
    }
}
