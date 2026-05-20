//
//  Views/Shared/DataRecoveryView.swift
//  KaKeBo
//
//  起動時にデータ消失を検知した際に表示する復元提案画面
//

import SwiftUI

struct DataRecoveryView: View {
    let lossResult: DataLossCheckResult
    let onRestore: (BackupFileInfo) -> Void
    let onSkip: () -> Void

    @State private var backups: [BackupFileInfo] = []
    @State private var selectedBackup: BackupFileInfo?
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // 警告アイコン
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                    .padding(.top, 32)

                // メッセージ
                VStack(spacing: 8) {
                    Text("データが見つかりません")
                        .font(.title2.bold())

                    Text(lossDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if backups.isEmpty {
                    // バックアップがない場合
                    VStack(spacing: 12) {
                        Image(systemName: "doc.questionmark")
                            .font(.title)
                            .foregroundStyle(.secondary)
                        Text("自動バックアップが見つかりません")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 32)
                } else {
                    // バックアップ一覧
                    List {
                        Section("復元可能なバックアップ") {
                            ForEach(backups) { backup in
                                Button {
                                    selectedBackup = backup
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(formatDate(backup.date))
                                                .font(.body)
                                                .foregroundStyle(.primary)
                                            Text("\(backup.transactionCount)件の取引 / \(backup.categoryCount)カテゴリ")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if selectedBackup?.id == backup.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }

                Spacer()

                // アクションボタン
                VStack(spacing: 12) {
                    if let selected = selectedBackup {
                        Button {
                            isRestoring = true
                            onRestore(selected)
                        } label: {
                            HStack {
                                if isRestoring {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "arrow.counterclockwise")
                                }
                                Text("このバックアップから復元")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isRestoring)
                    }

                    Button {
                        onSkip()
                    } label: {
                        Text("新しく始める")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                backups = AutoBackupManager.shared.availableBackups()
                selectedBackup = backups.first
            }
        }
    }

    private var lossDescription: String {
        switch lossResult {
        case .totalLoss(let count):
            return "以前は\(count)件の取引データがありましたが、現在は0件です。バックアップから復元できます。"
        case .significantLoss(let current, let lastKnown):
            return "取引データが\(lastKnown)件から\(current)件に減少しています。バックアップから復元できます。"
        default:
            return ""
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
