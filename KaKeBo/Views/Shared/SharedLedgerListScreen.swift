//
//  Views/Shared/SharedLedgerListScreen.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/25.
//

import SwiftUI
import CloudKit

struct SharedLedgerListScreen: View {
    @EnvironmentObject var store: SharedLedgerStore
    
    @State private var showNewLedgerSheet = false
    @State private var editingLedger: SharedLedger? = nil
    @State private var ledgerToDelete: SharedLedger? = nil
    @State private var showDeleteConfirm = false
    @State private var sharePayload: SharedLedgerStore.SharePayload? = nil
    @State private var showShareSheet = false
    @State private var shareErrorMessage: String? = nil
    @State private var showShareError = false
    
    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()
            
            content
            
            // コピー進捗のバナー
            if let copy = store.activeCopy {
                copyProgressView(copy: copy)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
        .task {
            await store.reloadLedgers()
        }
        // 新規作成シート
        .sheet(isPresented: $showNewLedgerSheet) {
            SharedLedgerEditorSheet(ledger: nil)
                .environmentObject(store)
        }
        // 編集シート
        .sheet(item: $editingLedger) { ledger in
            SharedLedgerEditorSheet(ledger: ledger)
                .environmentObject(store)
        }
        // 共有シート
        .sheet(isPresented: $showShareSheet) {
            if let payload = sharePayload {
                CloudSharingView(
                    share: payload.share,
                    container: CKContainer.default()
                )
            }
        }
        .confirmationDialog(
            "この共有家計簿を削除しますか？",
            isPresented: $showDeleteConfirm,
            presenting: ledgerToDelete
        ) { ledger in
            Button("削除", role: .destructive) {
                Task {
                    await store.deleteLedger(ledger)
                }
            }
            Button("キャンセル", role: .cancel) { }
        } message: { ledger in
            Text("「\(ledger.name)」を削除すると、共有家計簿に登録された取引も見えなくなります。")
        }
        .alert("共有の準備に失敗しました", isPresented: $showShareError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(shareErrorMessage ?? "不明なエラーが発生しました。時間をおいて再度お試しください。")
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.ledgers.isEmpty {
            ProgressView("読み込み中…")
                .tint(.accentColor)
        } else if store.ledgers.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    
                    ForEach(store.ledgers) { ledger in
                        ledgerCard(for: ledger)
                    }
                    
                    addLedgerButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
    }
    
    // MARK: - 状態別ビュー
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 12) {
                Image(systemName: "person.2.circle")
                    .font(.system(size: 52))
                    .foregroundStyle(.secondary)
                
                Text("共有家計簿がまだありません")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                
                Text("パートナーや家族と一緒に使う家計簿を作成すると、\nお互いの支出が同じカレンダーで確認できます。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            
            addLedgerButton
            
            Spacer()
        }
        .padding()
    }
    
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("共有家計簿")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            
            Text("複数人で一緒に使う家計簿をまとめて管理できます。カップル用、家族用、旅行用など、目的ごとに分けておくと便利です。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.04), lineWidth: 1)
                )
        )
    }
    
    // MARK: - カード
    
    private func ledgerCard(for ledger: SharedLedger) -> some View {
        Button {
            // カード全体タップ → 編集シート
            editingLedger = ledger
        } label: {
            HStack(spacing: 14) {
                // 左側カラー＋アイコン
                ZStack {
                    Circle()
                        .fill(color(from: ledger.colorHex).opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: ledger.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(color(from: ledger.colorHex))

                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(ledger.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.caption2)
                        Text("作成: \(ledger.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer(minLength: 8)
                
                // 右側に「招待」ボタンを常に表示
                if store.isOwned(ledger) {
                    Button {
                        presentShare(for: ledger)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.badge.plus")
                                .font(.caption)
                            Text("招待")
                                .font(.caption.weight(.semibold))
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.blue.opacity(0.12))
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                // 視覚的に「編集できそう」な矢印も足す
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingLedger = ledger
            } label: {
                Label("編集", systemImage: "pencil")
            }
            
            Button {
                presentShare(for: ledger)
            } label: {
                Label("招待・メンバー管理", systemImage: "person.2.badge.plus")
            }
            
            Button(role: .destructive) {
                ledgerToDelete = ledger
                showDeleteConfirm = true
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                ledgerToDelete = ledger
                showDeleteConfirm = true
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }
    
    // MARK: - 「新しい共有家計簿」ボタン
    
    private var addLedgerButton: some View {
        Button {
            showNewLedgerSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.headline)
                Text("新しい共有家計簿を作成")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 18)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.accentColor)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Hexカラー → Color 変換ヘルパ
    
    private func color(from hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexString = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        guard hexString.count == 6,
              let value = Int(hexString, radix: 16) else {
            return Color.accentColor
        }
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
    
    private func presentShare(for ledger: SharedLedger) {
        Task {
            do {
                let payload = try await store.prepareShare(for: ledger)
                await MainActor.run {
                    self.sharePayload = payload
                    self.showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    self.shareErrorMessage = error.localizedDescription
                    self.showShareError = true
                }
            }
        }
    }
    
    @ViewBuilder
    private func copyProgressView(copy: SharedLedgerStore.CopyState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                Text("「\(copy.ledgerName)」を同期中…")
                    .font(.caption)
                Spacer()
            }
            
            ProgressView(
                value: Double(copy.done),
                total: Double(copy.total)
            )
            .progressViewStyle(.linear)
            
            Text("\(copy.done) / \(copy.total) 件をコピー中")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary)
                .shadow(radius: 2)
        )
    }
}

private extension Color {
    static var tertiaryLabel: Color {
        Color(UIColor.tertiaryLabel)
    }
}
