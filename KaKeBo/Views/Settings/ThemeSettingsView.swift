//
//  Settings/ThemeSettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @State private var working: AppTheme = .init()
    @Environment(\.dismiss) private var dismiss
    
    // プレビュー専用（システム追従なし / ライト・ダーク手動切替）
    enum PreviewMode: String, CaseIterable, Identifiable {
        case light = "ライト"
        case dark  = "ダーク"
        var id: String { rawValue }
        var colorScheme: ColorScheme { self == .light ? .light : .dark }
    }
    @State private var previewMode: PreviewMode = .light
    
    var body: some View {
        Form {
            // --- アクセントカラー（共通 or 個別） ---
            Section("アクセントカラー") {
                Toggle("ライト/ダークで共通の色を使う", isOn: $working.useSameAccentForBoth)
                    .onChange(of: working.useSameAccentForBoth) { _, on in
                        if on { working.accentDarkRGBA = working.accentLightRGBA }
                    }
                
                ColorPicker(
                    working.useSameAccentForBoth ? "アクセント（共通）" : "アクセント（ライト）",
                    selection: Binding(
                        get: { working.accentLightRGBA.swiftUIColor },
                        set: {
                            working.accentLightRGBA = .init($0)
                            if working.useSameAccentForBoth {
                                working.accentDarkRGBA = working.accentLightRGBA
                            }
                        }
                    ),
                    supportsOpacity: false
                )
                .tint(working.accentLightRGBA.swiftUIColor)
                
                if !working.useSameAccentForBoth {
                    ColorPicker(
                        "アクセント（ダーク）",
                        selection: Binding(
                            get: { working.accentDarkRGBA.swiftUIColor },
                            set: { working.accentDarkRGBA = .init($0) }
                        ),
                        supportsOpacity: false
                    )
                }
            }
            
            // --- Home 背景色（共通 or 個別） ---
            Section("Home 背景色") {
                Toggle("ライト/ダークで共通の色を使う", isOn: $working.useSameBackgroundForBoth)
                    .onChange(of: working.useSameBackgroundForBoth) { _, on in
                        if on { working.backgroundDarkRGBA = working.backgroundLightRGBA }
                    }
                
                ColorPicker(
                    working.useSameBackgroundForBoth ? "背景色（共通）" : "背景色（ライト）",
                    selection: Binding(
                        get: { working.backgroundLightRGBA.swiftUIColor },
                        set: {
                            working.backgroundLightRGBA = .init($0)
                            if working.useSameBackgroundForBoth {
                                working.backgroundDarkRGBA = working.backgroundLightRGBA
                            }
                        }
                    ),
                    supportsOpacity: true
                )
                
                if !working.useSameBackgroundForBoth {
                    ColorPicker(
                        "背景色（ダーク）",
                        selection: Binding(
                            get: { working.backgroundDarkRGBA.swiftUIColor },
                            set: { working.backgroundDarkRGBA = .init($0) }
                        ),
                        supportsOpacity: true
                    )
                }
            }
            
            // --- プレビュー（ライト/ダーク切替） ---
            Section("プレビュー") {
                Picker("表示モード", selection: $previewMode) {
                    ForEach(PreviewMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                
                let scheme = previewMode.colorScheme
                HomePreview(
                    background: working.backgroundColor(for: scheme),
                    accent: working.accentColor(for: scheme)
                )
                .environment(\.colorScheme, scheme)
                .frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear { working = themeStore.theme }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("閉じる") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    themeStore.theme = working
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// 簡易プレビュー：HomeView のカード・ボタンをなんとなく再現
private struct HomePreview: View {
    var background: Color
    var accent: Color
    
    var body: some View {
        ZStack {
            Rectangle().fill(background)
            VStack(spacing: 10) {
                HStack {
                    Text("合計支出").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("追加") { }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                }
                .padding(.horizontal, 12)
                
                RoundedRectangle(cornerRadius: 12)
                    .fill(.thinMaterial)
                    .overlay(
                        VStack(spacing: 4) {
                            Text("¥12,345").font(.title2.weight(.semibold))
                            Text("今月の支出").font(.caption).foregroundStyle(.secondary)
                        }
                    )
                    .frame(height: 90)
                    .padding(.horizontal, 12)
            }
            .padding(.vertical, 10)
        }
    }
}
