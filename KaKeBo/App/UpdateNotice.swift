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
        .init(title: "背景の見た目を整えました", message: "履歴の行の背景が自然に見えるように整えました。", symbol: "rectangle.on.rectangle", tint: .teal),
        .init(title: "履歴の表示が軽くなりました", message: "履歴の一覧がスムーズに表示されるように整えました。", symbol: "speedometer", tint: .mint),
        .init(title: "背景の表示が安定しました", message: "履歴の行の背景が安定して表示されるように整えました。", symbol: "checkmark.circle", tint: .teal),
        .init(title: "履歴の表示が安定しました", message: "履歴の一覧が見やすくなるよう、表示のゆらぎを抑えました。", symbol: "checkmark.seal", tint: .green),
        .init(title: "下線の位置と長さを整えました", message: "ノートの線が必要なところだけに入るように見直し、読みやすくすっきりした見た目にしました。", symbol: "line.horizontal.3.decrease", tint: .orange),
        .init(title: "履歴の線をノートの下線に整えました", message: "履歴の見た目を、必要なところだけ下線が入るシンプルな表示に整えました。書き込んでいく感覚がもっと出ます。", symbol: "line.horizontal.3", tint: .brown),
        .init(title: "ホームのカードをシンプルに切り替え", message: "テーマ設定から、ホーム画面のカードをフラットで素直な見た目に切り替えられるようになりました。色の差だけで収入と支出が分かります。", symbol: "square.on.square", tint: .pink),
        .init(title: "履歴がない月でも迷わない", message: "今月の履歴がまだないときは、画面内にやさしい案内が表示されるようになりました。", symbol: "list.bullet.below.rectangle", tint: .orange),
        .init(title: "カレンダーに金額を数字で表示", message: "カレンダーの日ごとの金額をとても小さな文字でも数字で確認できるようにしました。", symbol: "textformat.123", tint: .green),
        .init(title: "日別推移がカテゴリの色でひと目で分かる", message: "ホームの棒グラフがカテゴリごとの色で表示され、どの支出が多い日なのか見分けやすくなりました。", symbol: "chart.bar.fill", tint: .teal),
        .init(title: "履歴のグラフが安定して表示される", message: "フィルター結果の棒グラフが最後まで正しく表示され、安心して確認できるようになりました。", symbol: "checkmark.circle.fill", tint: .blue),
        .init(title: "共有家計簿のデータつながりを整理", message: "カテゴリや取引が必ず共有ルートに結びつくようにそろえました。招待後の参加側でも同じ内容を受け取れるよう、裏側のつながりを整えています。", symbol: "link.badge.plus", tint: .green),
        .init(title: "共有家計簿の同期がすぐ反映される", message: "相手が追加した内容が、画面を開いたままでもすぐに反映されるようになりました。", symbol: "bolt.horizontal.circle.fill", tint: .blue),
        .init(title: "共有招待がうまくいかないときに再試行ボタンを表示", message: "招待リンクを開いたときの反応を詳しく記録し、失敗時はその場で再試行できるボタンを出すようにしました。開くを押しても進まないときの手がかりを残します。", symbol: "arrow.triangle.2.circlepath", tint: .orange),
        .init(title: "共有招待の参加がスムーズに", message: "招待リンクを開くだけで参加手続きが進み、すでに参加している場合もその場で分かるようになりました。", symbol: "person.2.badge.plus", tint: .indigo),
        .init(title: "大きいウィジェットでカレンダーを確認", message: "ホーム画面の最大サイズのウィジェットに当月カレンダーを表示できるようになり、日付を押すとその日の家計簿をすぐ開けます。", symbol: "calendar", tint: .blue),
        .init(title: "固定費の合計をひと目で確認", message: "固定費の管理シートに有効な固定費の合計金額を表示するようになり、毎月の支出をすぐに把握できます。", symbol: "yensign.circle.fill", tint: .mint),
        .init(title: "バックアップの家計簿選択を改善", message: "個人用・共有家計簿ごとに作成／復元を選べる新しいシートを追加し、失敗時に気付きやすいよう堅牢性を高めました。", symbol: "arrow.triangle.2.circlepath", tint: .purple),
        .init(title: "設定画面の下にバージョンを表示", message: "サポートへの連絡時などにすぐ確認できるよう、設定画面のいちばん下へ現在のバージョンをさりげなく記載しました。", symbol: "info.circle.fill", tint: .gray)
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
