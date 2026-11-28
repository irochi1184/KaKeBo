//
//  TutorialOverlay.swift
//  KaKeBo
//
//  初回起動では設定を求めず、最初の記録まで最短で案内する。
//

import SwiftUI
import UIKit

struct TutorialGate: View {
    @AppStorage("tutorial.completed") private var tutorialCompleted = false
    @AppStorage("tutorial.lastShownVersion") private var legacyLastShownVersion = ""
    @State private var isPresented = false

    var body: some View {
        TutorialOverlay(isPresented: $isPresented)
            .onAppear {
                if tutorialCompleted == false {
                    if legacyLastShownVersion.isEmpty {
                        isPresented = true
                    } else {
                        tutorialCompleted = true
                    }
                }
            }
            .onChange(of: isPresented) { _, newValue in
                if newValue == false {
                    tutorialCompleted = true
                    legacyLastShownVersion = AppVersion.current
                }
            }
    }
}

private struct TutorialOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject private var themeStore: ThemeStore
    @EnvironmentObject private var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject private var ledgerContext: LedgerContext
    @EnvironmentObject private var appRoute: AppRoute
    @Environment(\.colorScheme) private var scheme
    @AppStorage("monthStart.onboardingDone") private var monthStartOnboardingDone = false

    @State private var step: TutorialStep = .quickStart
    @State private var sharedName = "みんなの家計簿"
    @State private var isCreatingSharedLedger = false
    @State private var creationError: String?

    private var accent: Color { themeStore.theme.accentColor(for: scheme) }
    private var background: Color { themeStore.theme.backgroundColor(for: scheme) }

    var body: some View {
        ZStack {
            if isPresented {
                background.opacity(scheme == .dark ? 0.94 : 0.88)
                    .ignoresSafeArea()

                VStack(spacing: 18) {
                    header

                    switch step {
                    case .quickStart:
                        quickStartStep
                    case .sharedSetup:
                        sharedLedgerStep
                    }

                    if step == .sharedSetup {
                        sharedFooter
                    }
                }
                .padding(20)
                .frame(maxWidth: 520)
                .background {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(scheme == .dark ? Color.white.opacity(0.08) : Color(UIColor.systemBackground))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(accent.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: 24, y: 16)
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: step == .quickStart ? "sparkles" : "person.2.fill")
                .foregroundStyle(accent)
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text(step == .quickStart ? "KaKeBoへようこそ" : "共有家計簿を作成")
                    .font(.headline.weight(.semibold))
                Text(step == .quickStart ? "設定なしですぐ記録できます" : "名前だけ決めれば始められます")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                finish(openEntry: false)
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

    private var quickStartStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("まずは1件、記録してみましょう")
                    .font(.title3.weight(.bold))
                Text("月の開始日、カテゴリ、デザインは初期設定のままで使えます。必要になったときに設定画面から変更できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                ledgerContext.setPersonal()
                finish(openEntry: true)
            } label: {
                Label("最初の支出を登録する", systemImage: "plus.circle.fill")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accent)
                    )
            }
            .buttonStyle(.plain)

            Button {
                creationError = nil
                step = .sharedSetup
            } label: {
                Label("家族・パートナーと共有して始める", systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accent.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)

            Button("入力せずホームを見る") {
                ledgerContext.setPersonal()
                finish(openEntry: false)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
        }
    }

    private var sharedLedgerStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("共有する家計簿の名前")
                .font(.title3.weight(.bold))

            TextField("例：ふたりの家計簿", text: $sharedName)
                .textFieldStyle(.roundedBorder)
                .submitLabel(.done)

            Label("アイコン・色・カテゴリは、作成後にいつでも変更できます。", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let creationError {
                Text(creationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var sharedFooter: some View {
        HStack(spacing: 12) {
            Button("戻る") {
                creationError = nil
                step = .quickStart
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: createSharedLedger) {
                if isCreatingSharedLedger {
                    ProgressView()
                        .tint(.white)
                        .frame(minWidth: 96)
                } else {
                    Text("作成して記録する")
                        .fontWeight(.semibold)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(isCreatingSharedLedger)
        }
    }

    private func finish(openEntry: Bool) {
        monthStartOnboardingDone = true
        isPresented = false

        guard openEntry else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            appRoute.addTransactionRequested = true
        }
    }

    private func createSharedLedger() {
        let trimmed = sharedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            creationError = "家計簿名を入力してください"
            return
        }

        creationError = nil
        isCreatingSharedLedger = true

        Task {
            let ledger = await sharedLedgerStore.createLedger(
                name: trimmed,
                icon: "person.2.fill",
                colorHex: "#4F46E5"
            )

            await MainActor.run {
                isCreatingSharedLedger = false
                if let ledger {
                    sharedLedgerStore.rememberLastOpened(ledger: ledger)
                    ledgerContext.setShared(id: ledger.id)
                    finish(openEntry: true)
                } else {
                    creationError = "作成に失敗しました。通信環境をご確認ください。"
                }
            }
        }
    }
}

private enum TutorialStep {
    case quickStart
    case sharedSetup
}
