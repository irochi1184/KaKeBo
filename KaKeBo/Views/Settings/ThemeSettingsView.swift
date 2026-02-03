//
//  Settings/ThemeSettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI

struct ThemeSettingsView: View {
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var purchase: PurchaseManager
    @State private var working: AppTheme = .init()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var showPaywall = false
    
    enum PreviewMode: String, CaseIterable, Identifiable {
        case light = "ライト", dark = "ダーク"
        var id: String { rawValue }
        var colorScheme: ColorScheme { self == .light ? .light : .dark }
    }
    @State private var previewMode: PreviewMode = .light
    
    var body: some View {
        let accent = themeStore.theme.accentColor(for: scheme)
        Form {
            // === 無料プリセット（常に利用可） ===
            Section("無料プリセット") {
                PresetGrid(
                    selected: working.activePreset,
                    onSelect: { p in
                        var t = working
                        t.apply(p)
                        working = t
                    }
                )
            }

            // TODO: デザイン追加
//            Section("ホームカード") {
//                Picker("カードデザイン", selection: Binding(
//                    get: { working.homeCardStyle },
//                    set: { newVal in var w = working; w.homeCardStyle = newVal; working = w }
//                )) {
//                    ForEach(AppTheme.HomeCardStyle.allCases, id: \.self) {
//                        Text($0.title).tag($0)
//                    }
//                }
//                .pickerStyle(.segmented)
//            }
            
            // === カスタム（プレミアム限定） ===
            Section("カスタム（プレミアム）") {
                if purchase.isPremiumActive {
                    customEditors
                } else {
                    LockedCustomSection(accent: accent) {
                        showPaywall = true
                    }
                }
            }

            // === 入力・電卓設定 ===
            Section("入力・電卓") {
                Toggle("カスタム電卓キーパッドを使う", isOn: Binding(
                    get: { working.prefersCustomKeypad },
                    set: { newVal in var w = working; w.prefersCustomKeypad = newVal; working = w }
                ))

                if purchase.isPremiumActive {
                    ColorPicker(
                        "収入カラー",
                        selection: Binding(
                            get: { working.keypadIncomeRGBA.swiftUIColor },
                            set: { c in var w = working; w.keypadIncomeRGBA = .init(c); w.markAsCustom(); working = w }
                        ),
                        supportsOpacity: false
                    )
                    ColorPicker(
                        "支出カラー",
                        selection: Binding(
                            get: { working.keypadExpenseRGBA.swiftUIColor },
                            set: { c in var w = working; w.keypadExpenseRGBA = .init(c); w.markAsCustom(); working = w }
                        ),
                        supportsOpacity: false
                    )
                } else {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill").foregroundStyle(accent)
                        Text("プレミアムで電卓の収入/支出カラーを自由に変更できます。")
                    }
                }
            }

            // === プレビュー ===
            Section("プレビュー") {
                Picker("表示モード", selection: $previewMode) {
                    ForEach(PreviewMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                
                let s = previewMode.colorScheme
                HomePreview(
                    background: working.backgroundColor(for: s),
                    accent: working.accentColor(for: s),
                    cardStyle: working.homeCardStyle
                )
                .environment(\.colorScheme, s)
                .frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .onAppear { working = themeStore.theme }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    themeStore.theme = working
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(accent: themeStore.theme.accentColor(for: scheme))
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - カスタム編集UI（プレミアム時のみ）
    private var customEditors: some View {
        Group {
            // アクセント（ライト/ダーク個別OK、ただし「ダークでも同じ色にする」運用推奨時は useSameAccentForBoth=true を維持）
            Section {
                Toggle("ライト/ダークでアクセントを共通にする", isOn: Binding(
                    get: { working.useSameAccentForBoth },
                    set: { newVal in
                        var w = working; w.useSameAccentForBoth = newVal; if newVal { w.accentDarkRGBA = w.accentLightRGBA }; w.markAsCustom(); working = w
                    }
                ))
                ColorPicker(
                    working.useSameAccentForBoth ? "アクセント（共通）" : "アクセント（ライト）",
                    selection: Binding(
                        get: { working.accentLightRGBA.swiftUIColor },
                        set: { c in var w = working; w.accentLightRGBA = .init(c); if w.useSameAccentForBoth { w.accentDarkRGBA = w.accentLightRGBA }; w.markAsCustom(); working = w }
                    ),
                    supportsOpacity: false
                )
                if !working.useSameAccentForBoth {
                    ColorPicker(
                        "アクセント（ダーク）",
                        selection: Binding(
                            get: { working.accentDarkRGBA.swiftUIColor },
                            set: { c in var w = working; w.accentDarkRGBA = .init(c); w.markAsCustom(); working = w }
                        ),
                        supportsOpacity: false
                    )
                }
            }
            
            // 背景（要件：ライトは基本白系、ダークは暗め推奨。自由編集はプレミアムで可能）
            Section {
                Toggle("ライト/ダークで背景を共通にする", isOn: Binding(
                    get: { working.useSameBackgroundForBoth },
                    set: { newVal in
                        var w = working; w.useSameBackgroundForBoth = newVal; if newVal { w.backgroundDarkRGBA = w.backgroundLightRGBA }; w.markAsCustom(); working = w
                    }
                ))
                ColorPicker(
                    working.useSameBackgroundForBoth ? "背景（共通）" : "背景（ライト）",
                    selection: Binding(
                        get: { working.backgroundLightRGBA.swiftUIColor },
                        set: { c in var w = working; w.backgroundLightRGBA = .init(c); if w.useSameBackgroundForBoth { w.backgroundDarkRGBA = w.backgroundLightRGBA }; w.markAsCustom(); working = w }
                    ),
                    supportsOpacity: true
                )
                if !working.useSameBackgroundForBoth {
                    ColorPicker(
                        "背景（ダーク）",
                        selection: Binding(
                            get: { working.backgroundDarkRGBA.swiftUIColor },
                            set: { c in var w = working; w.backgroundDarkRGBA = .init(c); w.markAsCustom(); working = w }
                        ),
                        supportsOpacity: true
                    )
                }
            }
        }
    }
}

// MARK: - プリセットグリッド（無料）
private struct PresetGrid: View {
    let selected: AppTheme.Preset?
    let onSelect: (AppTheme.Preset) -> Void
    
    private let cols = [GridItem(.flexible()), GridItem(.flexible())]
    
    var body: some View {
        LazyVGrid(columns: cols, spacing: 10) {
            // “custom” を除外
            ForEach(AppTheme.Preset.allCases.filter { $0 != .custom }, id: \.self) { p in
                Button {
                    onSelect(p)
                } label: {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(p.accent)
                            .frame(width: 20, height: 20)
                        
                        Text(p.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        if selected == p {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(p.accent)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.thinMaterial)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}



// MARK: - ロック表示（非プレミアム時）
private struct LockedCustomSection: View {
    let accent: Color
    let onTapUpgrade: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "lock.fill").foregroundStyle(accent)
                Text("プレミアムプラン加入でアクセントカラーに背景色、ライトモードとダークモード時など自由なカラー編集がご利用いただけます。カラー指定も無限大で自由自在にカスタムできます。")
                Spacer()
            }
            Button("プレミアムを確認") { onTapUpgrade() }
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .padding(8)
    }
}

// 既存の簡易プレビューを流用
private struct HomePreview: View {
    var background: Color
    var accent: Color
    var cardStyle: AppTheme.HomeCardStyle
    var body: some View {
        ZStack {
            Rectangle().fill(background)
            VStack(spacing: 10) {
                HStack {
                    Text("合計支出").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("追加") { }.buttonStyle(.borderedProminent).tint(accent)
                }.padding(.horizontal, 12)
                VStack(spacing: 4) {
                    Text("¥12,345").font(.title2.weight(.semibold))
                    Text("今月の支出").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .modifier(HomePreviewCardStyle(cardStyle: cardStyle))
                .padding(.horizontal, 12)
            }
            .padding(.vertical, 10)
        }
    }
}

private struct HomePreviewCardStyle: ViewModifier {
    let cardStyle: AppTheme.HomeCardStyle
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        switch cardStyle {
        case .luxe:
            content
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(scheme == .dark ? Color.white.opacity(0.08) : .white.opacity(0.9))
                        .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                )
        case .flat:
            content
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(scheme == .dark ? Color.white.opacity(0.05) : .white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 1)
                )
        }
    }
}
