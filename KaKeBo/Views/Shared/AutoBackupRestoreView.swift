//
//  Views/Shared/AutoBackupRestoreView.swift
//  KaKeBo
//
//  自動バックアップ（ローカル＋iCloud）を任意のタイミングで一覧・復元する画面。
//  データ消失検知（DataRecoveryView）を待たずに、ユーザー操作で復元できるようにする。
//  復元は現在のデータを丸ごと置き換える破壊的操作のため、確認ダイアログを挟む。
//

import SwiftUI

struct AutoBackupRestoreView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss

    /// 一覧項目（バックアップ情報＋取得元）
    private struct Item: Identifiable {
        let info: BackupFileInfo
        let isCloud: Bool
        var id: URL { info.url }
    }

    @State private var items: [Item] = []
    @State private var selected: Item?
    @State private var isLoading = true
    @State private var isRestoring = false
    @State private var showConfirm = false
    @State private var resultMessage: String?
    @State private var showResult = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    loadingView
                } else if items.isEmpty {
                    emptyView
                } else {
                    listView
                }
            }
            .navigationTitle("自動バックアップから復元")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await load() }
            .alert("このバックアップから復元しますか？", isPresented: $showConfirm) {
                Button("復元する", role: .destructive) { performRestore() }
                Button("キャンセル", role: .cancel) { }
            } message: {
                Text("現在の家計簿データ（取引・カテゴリ・予算など）は、選んだバックアップの内容で置き換えられます。この操作は元に戻せません。")
            }
            .alert("復元", isPresented: $showResult) {
                Button("OK") { dismiss() }
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    // MARK: - サブビュー

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("バックアップを確認中…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.questionmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("復元できる自動バックアップがありません")
                .foregroundStyle(.secondary)
            Text("iCloud自動バックアップはONにした後、しばらく使うと作成されます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listView: some View {
        List {
            Section {
                ForEach(items) { item in
                    Button {
                        selected = item
                        showConfirm = true
                    } label: {
                        row(for: item)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRestoring)
                }
            } footer: {
                Text("復元すると現在のデータは置き換えられます。")
                    .font(.footnote)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if isRestoring {
                ProgressView("復元中…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func row(for item: Item) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.isCloud ? "icloud.fill" : "iphone")
                .foregroundStyle(item.isCloud ? .blue : .secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(formatDate(item.info.date))
                    .font(.body)
                Text("\(item.info.transactionCount)件の取引 / \(item.info.categoryCount)カテゴリ・\(item.isCloud ? "iCloud" : "この端末")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "arrow.counterclockwise")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    // MARK: - 読み込み・復元

    private func load() async {
        let local = AutoBackupManager.shared.availableBackups().map { Item(info: $0, isCloud: false) }
        let cloud = ICloudBackupManager.shared.availableBackups().map { Item(info: $0, isCloud: true) }

        // ローカル優先でマージし、ほぼ同時刻（60秒以内）の重複は1件に
        var merged = local
        for c in cloud where !merged.contains(where: { abs($0.info.date.timeIntervalSince(c.info.date)) < 60 }) {
            merged.append(c)
        }
        merged.sort { $0.info.date > $1.info.date }

        await MainActor.run {
            items = merged
            isLoading = false
        }
    }

    private func performRestore() {
        guard let item = selected else { return }
        isRestoring = true

        let payload: AutoBackupPayload? = item.isCloud
            ? ICloudBackupManager.shared.restore(from: item.info)
            : AutoBackupManager.shared.restore(from: item.info)

        guard let payload else {
            isRestoring = false
            resultMessage = "バックアップの読み込みに失敗しました。ファイルが破損しているか、iCloudからのダウンロードが完了していない可能性があります。"
            showResult = true
            return
        }

        store.restoreFromAutoBackup(payload: payload)
        isRestoring = false
        resultMessage = "復元が完了しました（取引 \(payload.transactions.count) 件）。テーマなど一部の設定はアプリ再起動後に反映されます。"
        showResult = true
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日 HH:mm"
        return f.string(from: date)
    }
}
