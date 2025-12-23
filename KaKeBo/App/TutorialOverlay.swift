//
//  TutorialOverlay.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/XX/XX.
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

// MARK: - メインのチュートリアルオーバーレイ

private struct TutorialOverlay: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var themeStore: ThemeStore
    @EnvironmentObject var monthStartStore: MonthStartStore
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @EnvironmentObject var ledgerContext: LedgerContext
    @Environment(\.colorScheme) private var scheme
    @AppStorage("monthStart.onboardingDone") private var monthStartOnboardingDone = false

    @State private var step: TutorialStep = .welcome
    @State private var usage: TutorialUsage = .personal
    @State private var showCategoryManager = false
    @State private var sharedName: String = "みんなの家計簿"
    @State private var sharedIcon: String = "person.2.fill"
    @State private var sharedColor: Color = Color.accentColor
    @State private var isCreatingSharedLedger = false
    @State private var creationError: String?

    private var accent: Color { themeStore.theme.accentColor(for: scheme) }
    private var background: Color { themeStore.theme.backgroundColor(for: scheme) }

    var body: some View {
        ZStack {
            if isPresented {
                background.opacity(scheme == .dark ? 0.92 : 0.86).ignoresSafeArea()

                VStack(spacing: 18) {
                    header

                    ScrollView {
                        VStack(spacing: 16) {
                            content
                        }
                        .padding(.horizontal, 4)
                    }

                    footer
                }
                .padding(18)
                .frame(maxWidth: 640)
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
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .scale))
                .sheet(isPresented: $showCategoryManager) {
                    NavigationStack {
                        CategoryListView()
                            .navigationTitle("カテゴリを設定")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isPresented)
    }

    // MARK: - UI Building Blocks

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(accent)
                    .font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("はじめての設定を行いましょう")
                        .font(.headline.weight(.semibold))
                    Text("初回の一度だけ表示されます")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if step != .summary {
                    Button {
                        finish()
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

            ProgressView(value: step.progress)
                .tint(accent)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .monthStart:
            MonthStartStep(settings: $monthStartStore.settings)
        case .usageChoice:
            usageStep
        case .sharedSetup:
            sharedLedgerStep
        case .categorySetup:
            categoryStep
        case .summary:
            summaryStep
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step.canGoBack && step != .summary {
                Button("戻る") {
                    goBack()
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            if let error = creationError, step == .sharedSetup {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            Button(action: goNext) {
                if isCreatingSharedLedger {
                    ProgressView()
                        .tint(.white)
                        .padding(.vertical, 8)
                        .frame(width: 70)
                } else {
                    Text(step.primaryActionTitle(for: usage))
                        .fontWeight(.semibold)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(step == .sharedSetup && isCreatingSharedLedger)
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("KaKeBoへようこそ！")
                .font(.title3.weight(.bold))
            Text("ダウンロードありがとうございます。これから最初の設定を一緒に進めましょう。下のボタンから開始してください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("月の開始日やカテゴリを決めて、自分に合った家計簿に整えられます。", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(accent)
                Label("共有設定もここからスタートできます。", systemImage: "person.2.fill")
                    .foregroundStyle(accent)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.opacity(0.12))
            )
        }
    }

    private var usageStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("家計簿の使い方を選択")
                .font(.title3.weight(.bold))
            Text("まずは個人で使うか、家族やパートナーと共有するかを選びましょう。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                usageCard(
                    title: "個人で使う",
                    message: "まずは自分だけでシンプルに登録を始めます。後から共有にも切り替え可能です。",
                    symbol: "person.crop.circle.fill",
                    selection: .personal
                )
                usageCard(
                    title: "共有で使う",
                    message: "家族や同棲・夫婦で同じ家計簿を見ながら管理します。",
                    symbol: "person.2.circle.fill",
                    selection: .shared
                )
            }
        }
    }

    private func usageCard(title: String, message: String, symbol: String, selection: TutorialUsage) -> some View {
        Button {
            usage = selection
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.headline)
                }
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selection == usage ? accent.opacity(0.15) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selection == usage ? accent : Color.secondary.opacity(0.2), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }

    private var sharedLedgerStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("共有家計簿を作成")
                .font(.title3.weight(.bold))
            Text("共有で使う場合は、まずみんなで使う家計簿を1つ作成しましょう。カテゴリや取引はコピーせず、ここから新しく始められます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                TextField("家計簿名", text: $sharedName)
                    .textFieldStyle(.roundedBorder)

                iconPicker

                HStack {
                    Text("テーマカラー")
                    Spacer()
                    ColorPicker("", selection: $sharedColor, supportsOpacity: false)
                        .labelsHidden()
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )

            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("個人用のカテゴリや取引はコピーせず、新しい共有家計簿として登録します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("アイコン")
                .font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(TutorialUsage.symbolCandidates, id: \.self) { symbol in
                        Button {
                            sharedIcon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            sharedIcon == symbol ? accent : Color.secondary.opacity(0.3),
                                            lineWidth: sharedIcon == symbol ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var categoryStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("カテゴリを整える")
                .font(.title3.weight(.bold))
            Text("出費や収入を把握しやすくするため、よく使うカテゴリを先に作成しておきましょう。共有家計簿を選択中なら共有用のカテゴリも編集できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                showCategoryManager = true
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                    Text("カテゴリ管理を開く")
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(accent.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var summaryStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("準備が整いました！")
                .font(.title3.weight(.bold))
            Text("そのほかにもリマインダー、Todo、固定費、テーマ、アプリロックなど様々な設定があるので自由に設定画面からカスタマイズしてください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                finish()
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("さぁ家計簿登録を始めよう！")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
    }

    // MARK: - Actions

    private func goNext() {
        creationError = nil

        switch step {
        case .welcome:
            step = .monthStart
        case .monthStart:
            monthStartOnboardingDone = true
            step = .usageChoice
        case .usageChoice:
            if usage == .personal {
                ledgerContext.setPersonal()
                step = .categorySetup
            } else {
                step = .sharedSetup
            }
        case .sharedSetup:
            createSharedLedger()
        case .categorySetup:
            step = .summary
        case .summary:
            finish()
        }
    }

    private func goBack() {
        switch step {
        case .monthStart:
            step = .welcome
        case .usageChoice:
            step = .monthStart
        case .sharedSetup:
            step = .usageChoice
        case .categorySetup:
            step = usage == .personal ? .usageChoice : .sharedSetup
        case .summary:
            step = .categorySetup
        case .welcome:
            break
        }
    }

    private func finish() {
        monthStartOnboardingDone = true
        isPresented = false
    }

    private func createSharedLedger() {
        let trimmed = sharedName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            creationError = "家計簿名を入力してください"
            return
        }

        isCreatingSharedLedger = true
        Task {
            let hex = TutorialUsage.hex(from: sharedColor)
            if let ledger = await sharedLedgerStore.createLedger(name: trimmed, icon: sharedIcon, colorHex: hex) {
                sharedLedgerStore.rememberLastOpened(ledger: ledger)
                ledgerContext.setShared(id: ledger.id)
                await MainActor.run {
                    step = .categorySetup
                }
            } else {
                await MainActor.run {
                    creationError = "作成に失敗しました。通信環境をご確認ください。"
                }
            }
            await MainActor.run {
                isCreatingSharedLedger = false
            }
        }
    }
}

// MARK: - Step / Usage enums

private enum TutorialStep: Int, CaseIterable {
    case welcome
    case monthStart
    case usageChoice
    case sharedSetup
    case categorySetup
    case summary

    var progress: Double {
        Double(rawValue + 1) / Double(TutorialStep.allCases.count)
    }

    var canGoBack: Bool { self != .welcome }

    func primaryActionTitle(for usage: TutorialUsage) -> String {
        switch self {
        case .welcome:
            return "設定を始める"
        case .monthStart:
            return "次へ"
        case .usageChoice:
            return usage == .personal ? "カテゴリ設定へ" : "共有家計簿を作成"
        case .sharedSetup:
            return "作成して進む"
        case .categorySetup:
            return "完了へ"
        case .summary:
            return "閉じる"
        }
    }
}

private enum TutorialUsage: String {
    case personal
    case shared

    static let symbolCandidates: [String] = [
        "wallet.pass", "yensign.circle", "yensign.circle.fill",
        "creditcard", "creditcard.fill",
        "cart", "cart.fill",
        "bag", "bag.fill",
        "house", "house.fill",
        "building.2", "building.2.fill",
        "tram.fill", "airplane",
        "heart.fill", "heart.circle.fill",
        "person.2", "person.2.fill",
        "gift.fill", "fork.knife",
        "fuelpump.fill"
    ]

    static func hex(from color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        let intR = Int(r * 255)
        let intG = Int(g * 255)
        let intB = Int(b * 255)
        return String(format: "#%02X%02X%02X", intR, intG, intB)
    }
}

// MARK: - Subviews

private struct MonthStartStep: View {
    @Binding var settings: MonthStartSettings

    private var resolver: MonthStartResolver {
        MonthStartResolver(settings: settings, holidayProvider: JapaneseHolidayProvider())
    }

    private var previewText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日（E）"
        let range = resolver.monthRange(for: Date())
        return "\(formatter.string(from: range.lowerBound)) 〜 \(formatter.string(from: range.upperBound))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("月の開始日を決める")
                .font(.title3.weight(.bold))
            Text("給料日や締め日に合わせて、ホーム画面で集計する基準日を指定できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("カスタム開始日を使う", isOn: Binding(
                    get: { settings.isCustomStartEnabled },
                    set: { settings.isCustomStartEnabled = $0 }
                ))

                if settings.isCustomStartEnabled {
                    Picker("集計の基準", selection: Binding(
                        get: { settings.boundaryType },
                        set: { settings.boundaryType = $0 }
                    )) {
                        ForEach(MonthBoundaryType.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("開始日", selection: Binding(
                        get: { settings.startDay },
                        set: { settings.startDay = $0 }
                    )) {
                        ForEach(1...31, id: \.self) { day in
                            Text("\(day)日").tag(day)
                        }
                    }
                    .pickerStyle(.wheel)

                    Picker("土日祝日に当たる場合", selection: Binding(
                        get: { settings.holidayAdjustment },
                        set: { settings.holidayAdjustment = $0 }
                    )) {
                        ForEach(MonthStartAdjustment.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text("今月は \(previewText) の期間で集計されます。")
                    Spacer()
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
        }
    }
}
