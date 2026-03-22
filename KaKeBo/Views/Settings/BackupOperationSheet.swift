//
//  Views/Settings/BackupOperationSheet.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/01/05.
//

import SwiftUI
import CloudKit

enum BackupMode: String, CaseIterable, Identifiable {
    case export
    case restore
    
    var id: String { rawValue }
    var title: String {
        switch self {
        case .export: return "バックアップを作成"
        case .restore: return "バックアップから復元"
        }
    }
    
    var systemImage: String {
        switch self {
        case .export: return "arrow.down.doc"
        case .restore: return "arrow.up.doc"
        }
    }
}

enum BackupTarget: Hashable {
    case personal
    case shared(CKRecord.ID)
}

struct BackupOperationSheet: View {
    let accent: Color
    @Binding var selection: BackupTarget
    @Binding var mode: BackupMode
    @Binding var isProcessing: Bool
    let onConfirm: () -> Void
    
    @EnvironmentObject var sharedLedgerStore: SharedLedgerStore
    @Environment(\.dismiss) private var dismiss
    
    private var options: [BackupTarget] {
        var list: [BackupTarget] = [.personal]
        list.append(contentsOf: sharedLedgerStore.ledgers.map { .shared($0.id) })
        return list
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(options, id: \.self) { target in
                        Button {
                            selection = target
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(targetTitle(for: target))
                                        .foregroundStyle(.primary)
                                    if let subtitle = targetSubtitle(for: target) {
                                        Text(subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selection == target {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("家計簿を選択")
                } footer: {
                    Text("共有家計簿が複数ある場合でも、ここで 1 件を選んで操作します。")
                        .font(.footnote)
                }
                
                Section("操作を選択") {
                    Picker("操作", selection: $mode) {
                        ForEach(BackupMode.allCases) { m in
                            Label(m.title, systemImage: m.systemImage)
                                .tag(m)
                        }
                    }
                    .pickerStyle(.inline)
                }
                
                Section {
                    Label {
                        Text("選択した家計簿に対して、作成または復元を実行します。")
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    
                    if isProcessing {
                        HStack {
                            ProgressView()
                            Text("処理中です…")
                        }
                    }
                }
            }
            .listRowBackground(FlatListRowBackground())
            .navigationTitle("バックアップを作成・復元")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("実行") {
                        dismiss()
                        onConfirm()
                    }
                    .disabled(isProcessing)
                }
            }
            .onAppear {
                if !options.contains(selection) {
                    selection = .personal
                }
            }
        }
    }
    
    private func targetTitle(for target: BackupTarget) -> String {
        switch target {
        case .personal:
            return "個人用家計簿"
        case .shared(let id):
            return sharedLedgerStore.ledgers.first(where: { $0.id == id })?.name ?? "共有家計簿"
        }
    }
    
    private func targetSubtitle(for target: BackupTarget) -> String? {
        switch target {
        case .personal:
            return "この端末に保存された家計簿データ"
        case .shared(let id):
            return sharedLedgerStore.ledgers.first(where: { $0.id == id }) != nil
            ? "iCloudで共有されている家計簿"
            : nil
        }
    }
}
