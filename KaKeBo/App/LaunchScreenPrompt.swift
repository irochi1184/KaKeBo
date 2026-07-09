//
//  LaunchScreenPrompt.swift
//  KaKeBo
//
//  起動時に開く画面の初回選択プロンプト（アップデート後に一度だけ表示）
//

import SwiftUI

// MARK: - 公開：一度だけ出すゲート（ルートに .overlay で載せる）
struct LaunchScreenPromptGate: View {
    @AppStorage(LaunchScreenOption.promptShownKey, store: .appGroup) private var promptShown = false
    // 新規インストール判定（TutorialGate と同じ条件）
    @AppStorage("tutorial.completed") private var tutorialCompleted = false
    @AppStorage("tutorial.lastShownVersion") private var legacyLastShownVersion = ""
    // アップデート通知（UpdateNoticeGate）との重なり回避用
    @AppStorage("lastShownVersion") private var lastShownVersion = ""
    @AppStorage("app.installedVersion") private var installedVersion = ""

    @State private var isPresented = false

    var body: some View {
        LaunchScreenPromptOverlay(isPresented: $isPresented)
            .onAppear { evaluate() }
            // アップデート通知が閉じられたタイミングで再評価する
            .onChange(of: lastShownVersion) { _, _ in evaluate() }
            .onChange(of: isPresented) { _, newValue in
                if newValue == false {
                    promptShown = true
                }
            }
    }

    private func evaluate() {
        guard !promptShown, !isPresented else { return }

        // 新規インストールはチュートリアルが表示されるため対象外（既定のホームのまま）
        let isFreshInstall = (tutorialCompleted == false && legacyLastShownVersion.isEmpty)
        if isFreshInstall {
            promptShown = true
            return
        }

        // アップデート通知がこれから表示される場合は、閉じられるまで待つ
        let updateNoticePending = !installedVersion.isEmpty
            && installedVersion != AppVersion.current
            && lastShownVersion != AppVersion.current
        if updateNoticePending { return }

        isPresented = true
    }
}

// MARK: - フルスクリーンの選択ビュー
struct LaunchScreenPromptOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var appRoute: AppRoute
    @Environment(\.colorScheme) private var scheme

    @AppStorage(LaunchScreenOption.storageKey, store: .appGroup)
    private var launchScreenRaw = LaunchScreenOption.home.rawValue

    @State private var selected: LaunchScreenOption = .home

    private var accent: Color { themeStore.theme.accentColor(for: scheme) }
    private var background: Color { themeStore.theme.backgroundColor(for: scheme) }

    var body: some View {
        ZStack {
            if isPresented {
                background.opacity(scheme == .dark ? 0.92 : 0.86).ignoresSafeArea()

                content
                    .padding(.horizontal, 18)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: isPresented)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 14)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(LaunchScreenOption.allCases) { option in
                        optionRow(option)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
            }

            VStack(spacing: 10) {
                primaryButton
                Text("あとから「設定 > 起動時に開く画面」でいつでも変更できます。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
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
                Text("NEW FEATURE")
                    .font(.caption2.weight(.bold))
                    .tracking(2.5)
                    .foregroundStyle(accent)
                Text("起動時に開く画面を選べます")
                    .font(.title3.weight(.bold))
                Text("アプリを起動したとき最初に表示する画面を選べるようになりました。よく使う画面を選んでください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private func optionRow(_ option: LaunchScreenOption) -> some View {
        let isSelected = (selected == option)
        return Button {
            selected = option
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : accent)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isSelected ? accent : accent.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? accent : Color.secondary.opacity(0.4))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.05) : Color.white.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.6) : Color.white.opacity(scheme == .dark ? 0.06 : 0.55), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var primaryButton: some View {
        Button {
            launchScreenRaw = selected.rawValue
            isPresented = false
            // 選んだ画面をその場で反映する（次回以降は起動時に自動適用）
            appRoute.tab = selected.tab
            if selected == .addTransaction {
                appRoute.addTransactionRequested = true
            }
        } label: {
            Text("この設定ではじめる")
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
