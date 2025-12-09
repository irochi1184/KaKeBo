//
//  UpdateNotice.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/30.
//

import SwiftUI

// MARK: - 公開：一度だけ出すゲート（ルートに .overlay で載せる）
struct UpdateNoticeGate: View {
    @AppStorage("lastShownVersion") private var lastShownVersion = ""
    @State private var isPresented = false
    
    var body: some View {
        UpdateNoticeOverlay(isPresented: $isPresented)
            .onAppear {
                let current = AppVersion.current
                if lastShownVersion != current {
                    isPresented = true
                }
            }
            .onChange(of: isPresented) { oldValue, newVal in
                if newVal == false {
                    lastShownVersion = AppVersion.current
                }
            }
    }
}

// MARK: - 半透明背景 + カード
struct UpdateNoticeOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    
    private var accent: Color { themeStore.theme.accentColor(for: scheme) }
    private var backdrop: Color { themeStore.theme.backgroundColor(for: scheme) }
    
    var body: some View {
        ZStack {
            if isPresented {
                backdrop.opacity(scheme == .dark ? 0.86 : 0.78).ignoresSafeArea()
                UpdateNoticeCard(isPresented: $isPresented, accent: accent)
                    .padding(.horizontal, 20)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: isPresented)
    }
}

// MARK: - カード本体（分割して型推論を軽く）
private struct UpdateNoticeCard: View {
    @Binding var isPresented: Bool
    let accent: Color
    @Environment(\.colorScheme) private var scheme
    
    // 文言はここだけ編集すればOK
    private var title: String { "KaKeBo \(AppVersion.current) アップデート" }
    private let hero: (title: String, message: String) = (
        title: "共有家計簿 で みんなと使える",
        message: "ホーム・カレンダー・レポート・履歴すべてで個人用と共有をワンタップ切替"
    )
    private let newFeatures: [String] = [
        "月の開始日を1〜31日から自由に設定でき、給料日や締め日に合わせやすくなりました",
        "カスタムキーボード（電卓）の ON / OFF を無料ユーザーでも切り替え可能に",
        "プレミアムではキーボードの色もお好みにカスタマイズできるように"
    ]
    private let improvements: [String] = [
        "レシート撮影（OCR）の精度を改善し、読み取り結果がより正確に",
        "固定費として設定できるカテゴリーの選択可能な範囲を拡張",
        "取引の追加・編集後、レポートのグラフが即座に更新されるように改善"
    ]

    var body: some View {
        VStack(spacing: 14) {
            CardHeader(title: title, accent: accent) {
                isPresented = false
            }
            
            // スクロール部分はセクションに分割
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HeroHighlight(hero: hero, accent: accent)

                    FeatureSection(title: "新機能",
                                   items: newFeatures,
                                   symbol: "sparkles",
                                   tint: accent)

                    FeatureSection(title: "改善",
                                   items: improvements,
                                   symbol: "arrow.triangle.2.circlepath",
                                   tint: .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 320)

            CardButtons(
                onOK: { isPresented = false },
                accent: accent
            )
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AnyShapeStyle(scheme == .dark
                                    ? AnyShapeStyle(Color.white.opacity(0.10))
                                    : AnyShapeStyle(.ultraThinMaterial)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.12), radius: 20, y: 12)
    }
}

// MARK: - パーツ：ヒーロー
private struct HeroHighlight: View {
    let hero: (title: String, message: String)
    let accent: Color
    @Environment(\.colorScheme) private var scheme

    private var gradient: LinearGradient {
        LinearGradient(colors: [accent.opacity(0.28), accent.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(accent))
                VStack(alignment: .leading, spacing: 4) {
                    Text(hero.title)
                        .font(.headline.weight(.semibold))
                    Text(hero.message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            TagRow()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(gradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(accent.opacity(scheme == .dark ? 0.55 : 0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - パーツ：タグ行
private struct TagRow: View {
    var body: some View {
        HStack(spacing: 6) {
            TagView(text: "共有家計簿", systemName: "person.3.fill", tint: .white.opacity(0.9), background: Color.white.opacity(0.18))
            TagView(text: "ホーム/カレンダー/レポート/履歴", systemName: "rectangle.split.3x1.fill", tint: .white.opacity(0.92), background: Color.white.opacity(0.14))
        }
    }
}

private struct TagView: View {
    let text: String
    let systemName: String
    let tint: Color
    let background: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
            Text(text).font(.caption.weight(.medium))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .foregroundStyle(tint)
        .background(
            Capsule().fill(background)
        )
    }
}

// MARK: - パーツ：ヘッダ
private struct CardHeader: View {
    let title: String
    let accent: Color
    let onClose: () -> Void
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
            Text(title).font(.headline)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("閉じる")
        }
    }
}

// MARK: - パーツ：セクション（機能リスト）
private struct FeatureSection: View {
    let title: String
    let items: [String]
    let symbol: String
    let tint: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(items, id: \.self) { line in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: symbol)
                            .foregroundStyle(tint)
                        Text(line)
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

// MARK: - パーツ：ボタン行
private struct CardButtons: View {
    let onOK: () -> Void
    let accent: Color
    
    var body: some View {
        Button(action: onOK) {
            HStack { Image(systemName: "hand.thumbsup.fill"); Text("OK") }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
    }
}

// MARK: - ユーティリティ
private enum AppVersion {
    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }
}
