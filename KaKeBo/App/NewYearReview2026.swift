//
//  NewYearReview2026.swift
//  KaKeBo
//
//  Created by GPT on 2024/05/06.
//

import SwiftUI

/// 2026年の初回起動時に一度だけ表示するレビュー導線
struct NewYearReview2026Gate: View {
    @AppStorage("engagement.newYear2026Review.shown", store: .appGroup) private var hasShown = false
    @AppStorage("engagement.lastActiveYear", store: .appGroup) private var lastActiveYear = 0
    @AppStorage("app.installedVersion") private var installedVersion = ""
    @State private var isPresented = false

    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    private let calendar = Calendar.current

    private var accent: Color { themeStore.theme.accentColor(for: scheme) }
    private var background: Color { themeStore.theme.backgroundColor(for: scheme) }

    var body: some View {
        NewYearReview2026Overlay(
            isPresented: $isPresented,
            accent: accent,
            background: background,
            appStoreURL: URL(string: "https://apps.apple.com/app/id6754249349")!
        )
        .onAppear(perform: evaluateAndMaybeShow)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                evaluateAndMaybeShow()
            }
        }
    }

    private func evaluateAndMaybeShow() {
        let year = calendar.component(.year, from: Date())
        let previousActiveYear = lastActiveYear
        if lastActiveYear != year {
            lastActiveYear = year
        }

        guard !hasShown else { return }
        guard year == 2026 else { return }
        guard previousActiveYear == 2025 else { return }
        guard !installedVersion.isEmpty else { return }
        guard installedVersion != AppVersion.current else { return }

        hasShown = true
        isPresented = true
    }
}

private struct NewYearReview2026Overlay: View {
    @Binding var isPresented: Bool
    let accent: Color
    let background: Color
    let appStoreURL: URL

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            if isPresented {
                background.opacity(scheme == .dark ? 0.9 : 0.85)
                    .ignoresSafeArea()

                content
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            message
            buttons
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(accent.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(scheme == .dark ? 0.55 : 0.15), radius: 24, y: 12)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(accent)
                .padding(10)
                .background(Circle().fill(accent.opacity(0.15)))

            VStack(alignment: .leading, spacing: 4) {
                Text("新年のごあいさつ")
                    .font(.title3.weight(.semibold))
                Text("KaKeBo より感謝を込めて")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("明けましておめでとうございます。")
            Text("KaKeBoのサービスが始まってから2ヶ月が経過しました。")
            Text("これからも、より一層ご満足いただけるよう努めてまいります。ご意見・ご感想がありましたら、レビューでお聞かせいただけると嬉しいです。")
        }
        .font(.body)
        .foregroundStyle(.primary)
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button {
                isPresented = false
            } label: {
                Text("また今度にする")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)

            Button(action: openStore) {
                Text("レビューに協力する")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
    }

    private func openStore() {
        openURL(appStoreURL)
        isPresented = false
    }
}
