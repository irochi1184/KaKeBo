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
    private let newFeatures: [String] = [
        "アプリ全体の履歴表示タブ追加",
        "履歴タブにてメモ・カテゴリ・タグ検索で絞り込みが可能",
        "履歴タブにてフィルター機能追加（カテゴリ・タグ・期間・金額範囲）",
        "各支出入に「タグ追加・編集」機能を追加（プレミアムプランでサブカテゴリーのように無制限にタグを付与できます。）"
    ]
    private let others: [String] = [
        "カテゴリー推移の年表示にカンマがついていたものを除去",
        "タグ機能追加に伴い、一部レイアウトを修正"
    ]
    
    @State private var showDetail = false
    
    var body: some View {
        VStack(spacing: 14) {
            CardHeader(title: title, accent: accent) {
                isPresented = false
            }
            
            // スクロール部分はセクションに分割
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    FeatureSection(title: "新機能",
                                   items: newFeatures,
                                   symbol: "checkmark.seal.fill",
                                   tint: accent)
                    
                    FeatureSection(title: "その他",
                                   items: others,
                                   symbol: "wrench.adjustable",
                                   tint: .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)
            
            CardButtons(
                onDetail: { showDetail = true },
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
    let onDetail: () -> Void
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
