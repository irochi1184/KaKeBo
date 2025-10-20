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
    
    var body: some View {
        Form {
            Section("外観モード") {
                Toggle("システムのダークモードに合わせる", isOn: $working.allowSystemDarkMode)
                if !working.allowSystemDarkMode {
                    Picker("外観を固定", selection: $working.forceDarkMode) {
                        Text("ライト").tag(false)
                        Text("ダーク").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            }
            Section("アクセントカラー") {
                ColorPicker("基調色（ボタン/リンクの色）",
                            selection: Binding(
                                get: { working.accentRGBA.swiftUIColor },
                                set: { working.accentRGBA = .init($0) }
                            ),
                            supportsOpacity: false
                )
                .tint(working.accentRGBA.swiftUIColor)
            }
            
            // プレビュー（HomeView 風の簡易見本）
            Section("プレビュー") {
                HomePreview()
                    .environment(\.colorScheme, previewScheme(for: working) ?? .light)
                    .tint(working.accentRGBA.swiftUIColor)
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
    
    private func previewScheme(for t: AppTheme) -> ColorScheme? {
        t.allowSystemDarkMode ? nil : (t.forceDarkMode ? .dark : .light)
    }
}

// 簡易プレビュー：HomeView のカード・ボタンをなんとなく再現
private struct HomePreview: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            VStack(spacing: 10) {
                HStack {
                    Text("合計支出").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("追加") { }.buttonStyle(.borderedProminent)
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
