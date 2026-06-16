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
        Highlight(
            title: "ホーム画面のカードを並び替え",
            message: "設定画面からホームのカードを自由に並び替え。よく見る情報を上に配置できます。",
            symbol: "rectangle.stack.fill",
            tint: .blue
        ),
        Highlight(
            title: "不要なカードを非表示に",
            message: "使わないカードはオフにしてすっきり。自分仕様のホーム画面に整えられます。",
            symbol: "eye.slash.fill",
            tint: .indigo
        ),
        Highlight(
            title: "予算から支出一覧をすぐ確認",
            message: "予算タブのカテゴリをタップすると、その月の支出明細をその場で確認できます。",
            symbol: "list.bullet.rectangle",
            tint: .green
        ),
        Highlight(
            title: "予算リストの並び替え",
            message: "予算が高い順・支出が多い順・使用率順など、見たい順番で予算を並び替えられます。",
            symbol: "arrow.up.arrow.down",
            tint: .orange
        )
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
     アップデート 2.1.5
     - 招待リンクをアプリ内で開けるように改善
     - 共有家計簿に参加できない問題を修正
     アップデート 2.2.0
     - テーマ管理に「フラット」を追加
     - 収支カラーのカスタムに対応（プレミアム）
     - 日別推移の詳細を確認しやすく
     アップデート 2.3.0
     - 支出予測・予算アラート機能を追加
     - レシートOCR精度を大幅に向上
     - PayPay等の決済アプリスクリーンショットからの自動入力に対応
     - 繰り返し支出の自動検出機能を追加
     アップデート 2.3.1
     - CSV/PDFデータ書き出し機能を追加
     - 年間レポートPDF書き出し機能を追加
     - 週間サマリーカードをホーム画面に追加
     - PDF出力をアプリ内テーマカラーに統一
     - アップデート時の不要な画面表示を修正
     - 複数箇所の文字化けを修正
     アップデート 2.3.3
     - 自動バックアップ機能を追加（最大5世代、1時間間隔）
     - 起動時データ消失検知＋復元提案UIを追加
     - バックアップ範囲を拡大（電卓カラー・収支カラー・テーマスタイル等）
     - AppGroup ID誤変更防止ガードを追加
     - レポート画面のPDF共有シートが空白になる問題を修正
     アップデート 2.4（2.3.4 の内容を統合）
     - ロック画面ウィジェット対応（円形ゲージ・横長・インライン）
     - iCloud Drive自動バックアップ機能を追加
     - 機種変更時のiCloudからの自動復元提案を追加
     - カテゴリ削除時に取引を「未分類」に移動するオプションを追加
     - 自動バックアップ処理をバックグラウンドキュー化
     - データ復元画面にiCloudバックアップを統合表示
     - アプリ全体のフォント変更機能を追加（無料3種＋プレミアム18種）
     - 固定費の繰り返し回数・期日設定を追加（自動無効化対応）
     - お気に入り絞り込み条件の保存・呼び出し機能を追加
     - 固定費のタグをバックアップに含めるよう改善
     - アップデート履歴を設定画面から閲覧可能に
     - 起動時の白画面問題を修正
     アップデート 3.0
     - カテゴリ別予算管理タブを追加
     - 予算の超過・使いすぎをホーム画面に通知する予算アラートを追加
     - 先月の支出をワンタップで予算に設定する機能を追加
     - カテゴリごとに予算をオン・オフできる一時停止機能を追加
     - カテゴリ追加・編集画面から予算を設定できるように
     - メニューをサイドメニューに整理
     - iCloud自動バックアップが保存されない問題を修正
     アップデート 3.1
     - ホーム画面のカードを設定画面から並び替えできるように
     - ホーム画面の不要なカードを非表示にできる機能を追加
     - カードの並び替え・表示切り替えがホーム画面にすぐ反映されるよう改善
     - 予算タブでカテゴリをタップするとその月の支出一覧を確認できるように
     - 予算タブのカテゴリを予算順・支出順・使用率順で並び替えできるように
     */

    let accent: Color
    @Binding var isPresented: Bool
    let highlights: [Highlight]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 16)

            ScrollView {
                VStack(spacing: 12) {
                    hero
                    VStack(spacing: 10) {
                        ForEach(highlights) { highlight in
                            highlightRow(highlight)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }

            primaryButton
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 22)
        }
        .frame(maxWidth: 460, maxHeight: 660)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.5),
                            accent.opacity(0.05),
                            .white.opacity(scheme == .dark ? 0.08 : 0.45)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.18), radius: 30, y: 18)
    }

    // 高級感のあるカード背景（マテリアル＋アクセントの淡いグロー）
    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(scheme == .dark ? Color(white: 0.12) : Color(white: 0.99))

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(scheme == .dark ? 0.0 : 0.6)

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(scheme == .dark ? 0.20 : 0.12), .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("WHAT'S NEW")
                    .font(.caption2.weight(.bold))
                    .tracking(2.5)
                    .foregroundStyle(accent)
                Text("アップデートのお知らせ")
                    .font(.title3.weight(.bold))
            }

            Spacer()

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.secondary.opacity(0.12)))
            }
            .accessibilityLabel("閉じる")
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [accent, accent.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                )
                .shadow(color: accent.opacity(0.45), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 3) {
                Text("バージョン \(AppVersion.current)")
                    .font(.title.weight(.heavy))
                Text("もっと、自分好みに使いやすく。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(scheme == .dark ? 0.22 : 0.16), accent.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func highlightRow(_ highlight: Highlight) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: highlight.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [highlight.tint, highlight.tint.opacity(0.65)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: highlight.tint.opacity(0.35), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(highlight.title)
                    .font(.subheadline.weight(.bold))
                Text(highlight.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(scheme == .dark ? 0.06 : 0.55), lineWidth: 1)
        )
    }

    private var primaryButton: some View {
        Button {
            isPresented = false
        } label: {
            Text("はじめる")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.78)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .shadow(color: accent.opacity(0.4), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - バージョン履歴データ
struct VersionEntry: Identifiable {
    let id = UUID()
    let version: String
    let items: [String]
}

/// 過去のアップデート履歴（新しい順）
let versionHistory: [VersionEntry] = [
    VersionEntry(version: "3.1", items: [
        "ホーム画面のカードを設定画面から並び替えできるように",
        "ホーム画面の不要なカードを非表示にできる機能を追加",
        "カードの並び替え・表示切り替えがホーム画面にすぐ反映されるよう改善",
        "予算タブでカテゴリをタップするとその月の支出一覧を確認できるように",
        "予算タブのカテゴリを予算順・支出順・使用率順で並び替えできるように",
    ]),
    VersionEntry(version: "3.0", items: [
        "カテゴリ別予算管理タブを追加",
        "予算の超過・使いすぎをホーム画面に通知する予算アラートを追加",
        "先月の支出をワンタップで予算に設定する機能を追加",
        "カテゴリごとに予算をオン・オフできる一時停止機能を追加",
        "カテゴリ追加・編集画面から予算を設定できるように",
        "メニューをサイドメニューに整理",
        "iCloud自動バックアップが保存されない問題を修正",
    ]),
    VersionEntry(version: "2.4", items: [
        "ロック画面ウィジェット対応（円形ゲージ・横長・インライン）",
        "iCloud Drive自動バックアップ機能を追加",
        "機種変更時のiCloudからの自動復元提案を追加",
        "カテゴリ削除時に取引を「未分類」に移動するオプションを追加",
        "アプリ全体のフォント変更機能を追加（標準・丸ゴシック・セリフ・等幅）",
        "固定費の繰り返し回数・期日設定を追加（自動無効化対応）",
        "お気に入り絞り込み条件の保存・呼び出し機能を追加",
        "固定費のタグをバックアップに含めるよう改善",
        "アップデート履歴を設定画面から閲覧可能に",
    ]),
    VersionEntry(version: "2.3.3", items: [
        "自動バックアップ機能を追加（最大5世代、1時間間隔）",
        "起動時データ消失検知＋復元提案UIを追加",
        "バックアップ範囲を拡大（電卓カラー・収支カラー・テーマスタイル等）",
        "AppGroup ID誤変更防止ガードを追加",
        "レポート画面のPDF共有シートが空白になる問題を修正",
    ]),
    VersionEntry(version: "2.3.1", items: [
        "CSV/PDFデータ書き出し機能を追加",
        "年間レポートPDF書き出し機能を追加",
        "週間サマリーカードをホーム画面に追加",
        "PDF出力をアプリ内テーマカラーに統一",
        "アップデート時の不要な画面表示を修正",
        "複数箇所の文字化けを修正",
    ]),
    VersionEntry(version: "2.3.0", items: [
        "支出予測・予算アラート機能を追加",
        "レシートOCR精度を大幅に向上",
        "PayPay等の決済アプリスクリーンショットからの自動入力に対応",
        "繰り返し支出の自動検出機能を追加",
    ]),
    VersionEntry(version: "2.2.0", items: [
        "テーマ管理に「フラット」を追加",
        "収支カラーのカスタムに対応（プレミアム）",
        "日別推移の詳細を確認しやすく",
    ]),
    VersionEntry(version: "2.1.5", items: [
        "招待リンクをアプリ内で開けるように改善",
        "共有家計簿に参加できない問題を修正",
    ]),
    VersionEntry(version: "2.1.4", items: [
        "日別推移がカテゴリの色でひと目で分かる",
        "大きいウィジェットでカレンダーを確認",
        "固定費の合計をひと目で確認",
        "バックアップの家計簿選択を改善",
        "設定画面の下にバージョンを表示",
    ]),
    VersionEntry(version: "2.1.1", items: [
        "カレンダーの下部に表示する内容を好みに合わせて切り替えられるようになりました",
        "フィルターした結果をそのままグラフに出力できます（無料プランは毎月3回まで）",
        "参加画面の案内や配置を調整し、スムーズに入れるようになりました",
    ]),
    VersionEntry(version: "2.1.0", items: [
        "共有招待の参加を改善",
        "共有家計簿での削除・整理",
        "固定費へのタグ付け（プレミアム）",
        "バックアップ範囲を拡大",
        "テーマ設定の維持",
        "Todo テンプレートの追加タイミングを調整",
        "よく使う取引ショートカット",
    ]),
]

// MARK: - ユーティリティ
enum AppVersion {
    static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
    }
}
