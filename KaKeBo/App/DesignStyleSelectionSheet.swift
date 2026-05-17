//
//  DesignStyleSelectionSheet.swift
//  KaKeBo
//
//  Created by Codex on 2026/03/23.
//

import SwiftUI
import UIKit

struct DesignStyleSelectionSheet: View {
    @Binding var isPresented: Bool
    let title: String
    let message: String
    let primaryButtonTitle: String
    var onApplied: (() -> Void)? = nil

    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @State private var selectedStyle: AppTheme.VisualStyle = .modern

    private var accent: Color { themeStore.theme.accentColor(for: scheme) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    StyleChoiceCard(
                        style: .modern,
                        selectedStyle: $selectedStyle,
                        imageNames: ["design-standard-1", "design-standard-2"]
                    )

                    StyleChoiceCard(
                        style: .business,
                        selectedStyle: $selectedStyle,
                        imageNames: ["design-flat-1", "design-flat-2"]
                    )
                }
                .padding()
            }
            .navigationTitle("デザインを選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("あとで") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(primaryButtonTitle) {
                        applySelection()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            selectedStyle = themeStore.theme.visualStyle
        }
    }

    private func applySelection() {
        var theme = themeStore.theme
        theme.visualStyle = selectedStyle
        if selectedStyle == .modern {
            theme.homeCardStyle = .luxe
        }
        themeStore.theme = theme
        onApplied?()
        isPresented = false
    }
}

private struct StyleChoiceCard: View {
    let style: AppTheme.VisualStyle
    @Binding var selectedStyle: AppTheme.VisualStyle
    let imageNames: [String]

    var body: some View {
        Button {
            selectedStyle = style
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: selectedStyle == style ? "checkmark.circle.fill" : "circle")
                    Text(style.title)
                        .font(.headline)
                    Spacer()
                }

                Text(styleDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(imageNames, id: \.self) { imageName in
                        screenshotPreview(name: imageName)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selectedStyle == style ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: selectedStyle == style ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func screenshotPreview(name: String) -> some View {
        if let preview = UIImage(named: name) {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(maxWidth: .infinity, minHeight: 140, maxHeight: 140)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(name)
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .padding(8)
                )
        }
    }

    private var styleDescription: String {
        switch style {
        case .modern:
            return "立体感のある標準デザインです。"
        case .business:
            return "装飾を抑えたフラットデザインです。"
        }
    }
}
