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
    @AppStorage("app.installedVersion") private var installedVersion = ""
    @State private var isPresented = false

    var body: some View {
        UpdateNoticeOverlay(isPresented: $isPresented)
            .onAppear {
                if installedVersion.isEmpty {
                    installedVersion = AppVersion.current
                    return
                }

                if installedVersion != AppVersion.current && lastShownVersion != AppVersion.current {
                    isPresented = true
                }
            }
            .onChange(of: isPresented) { _, newVal in
                if newVal == false {
                    lastShownVersion = AppVersion.current
                    installedVersion = AppVersion.current
                }
            }
    }
}

// MARK: - フルスクリーンのアップデートビュー
struct UpdateNoticeOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme

    private var accent: Color { themeStore.theme.accentColor(for: scheme) }
    private var background: Color { themeStore.theme.backgroundColor(for: scheme) }

    var body: some View {
        ZStack {
            if isPresented {
                background.opacity(scheme == .dark ? 0.92 : 0.86).ignoresSafeArea()

                UpdateNoticeContent(
                    accent: accent,
                    isPresented: $isPresented,
                    highlights: UpdateNoticeContent.defaultHighlights
                )
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isPresented)
    }
}

// MARK: - 中身
private struct UpdateNoticeContent: View {
    struct Highlight: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let symbol: String
        let tint: Color
    }

    static let defaultHighlights: [Highlight] = [
        .init(
            title: "招待リンクをアプリ内で開けるように改善",
            message: "共有家計簿の招待リンクを、よりスムーズにアプリ内で開けるようになりました。",
            symbol: "link.badge.plus",
            tint: .blue
        ),
        .init(
            title: "共有家計簿に参加できない問題を修正",
            message: "一部のバージョンで、招待リンクから共有家計簿に参加できないことがある問題を修正しました。",
            symbol: "person.2.badge.gearshape",
            tint: .green
        ),
    ]
    /*
     アップデート 2.1.0
     - 共有招待の参加を改善
     - 共有家計簿での削除・整理
     - 固定費へのタグ付け（プレミアム）
     - バックアップ範囲を拡大
     - テーマ設定の維持
     - Todo テンプレートの追加タイミングを調整
     - よく使う取引ショートカット
     アップデート 2.1.1
     - カレンダーの下部に表示する内容を好みに合わせて切り替えられるようになりました。
     - フィルターした結果をそのままグラフに出力できます。（無料プランは毎月3回まで）
     - 参加画面の案内や配置を調整し、スムーズに入れるようになりました。
     アップデート 2.1.4
     - 日別推移がカテゴリの色でひと目で分かる
     - 大きいウィジェットでカレンダーを確認
     - 固定費の合計をひと目で確認
     - バックアップの家計簿選択を改善
     - 設定画面の下にバージョンを表示
     */

    let accent: Color
    @Binding var isPresented: Bool
    let highlights: [Highlight]
    @Environment(\.colorScheme) private var scheme

    private var title: String { "KaKeBo \(AppVersion.current) アップデート" }

    var body: some View {
        VStack(spacing: 16) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    ForEach(highlights) { highlight in
                        highlightRow(highlight)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            primaryButton
        }
        .padding(18)
        .background {
            if scheme == .dark {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            } else {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.15), radius: 24, y: 16)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
                .padding(8)
                .background(Circle().fill(accent.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text("アップデートのお知らせ")
                    .font(.headline.weight(.semibold))
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Circle().fill(.secondary.opacity(0.1)))
            }
            .accessibilityLabel("閉じる")
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("バージョン \(AppVersion.current) の主な改善点")
                .font(.title3.weight(.bold))
            Text("カレンダー表示のカスタマイズ、フィルター結果のグラフ出力、共有家計簿の参加体験を改善しました。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [accent.opacity(0.25), accent.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .cornerRadius(16)
        )
    }

    private func highlightRow(_ highlight: Highlight) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: highlight.symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(highlight.tint)
                .frame(width: 36, height: 36)
                .background(Circle().fill(highlight.tint.opacity(0.12)))

            VStack(alignment: .leading, spacing: 6) {
                Text(highlight.title)
                    .font(.headline)
                Text(highlight.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private var primaryButton: some View {
        Button {
            isPresented = false
        } label: {
            HStack {
                Image(systemName: "hand.thumbsup.fill")
                Text("OK")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(accent)
    }
}

// MARK: - ユーティリティ
enum AppVersion {
    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }
}
