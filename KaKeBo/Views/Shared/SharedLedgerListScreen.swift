//
//  Views/Shared/SharedLedgerListScreen.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/25.
//

import SwiftUI
import CloudKit
import UIKit

struct SharedLedgerListScreen: View {
    @EnvironmentObject var store: SharedLedgerStore

    @State private var showNewLedgerSheet = false
    @State private var editingLedger: SharedLedger? = nil
    @State private var ledgerToDelete: SharedLedger? = nil
    @State private var showDeleteConfirm = false
    @State private var shareTargetLedger: SharedLedger? = nil
    @State private var sharePayload: SharedLedgerStore.SharePayload? = nil
    @State private var shareLoading = false
    @State private var shareErrorMessage: String? = nil
    @State private var showShareError = false
    @State private var deleteErrorMessage: String? = nil
    @State private var showDeleteError = false
    @State private var showJoinByLinkSheet = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemGroupedBackground)
                .ignoresSafeArea()

            content

            if shareLoading {
                sharingLoadingView
                    .padding(.horizontal, 20)
            }

            if store.isLoading && !store.ledgers.isEmpty {
                LoadingOverlayView(
                    title: "読み込み中",
                    message: "共有家計簿の最新情報を更新しています…"
                )
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
        .sheet(item: $sharePayload, onDismiss: { sharePayload = nil }) { payload in
            ShareInvitationSheet(
                payload: payload,
                ledger: shareTargetLedger
            )
            .environmentObject(store)
        }
        .sheet(isPresented: $showJoinByLinkSheet) {
            JoinSharedLedgerByLinkSheet()
                .environmentObject(store)
        }
        .confirmationDialog(
            "この共有家計簿を削除しますか？",
            isPresented: $showDeleteConfirm,
            presenting: ledgerToDelete
        ) { ledger in
            Button("削除", role: .destructive) {
                Task {
                    await handleDelete(ledger)
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
        .alert("削除に失敗しました", isPresented: $showDeleteError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage ?? "通信環境をご確認のうえ、時間をおいて再度お試しください。")
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

                    if !store.ownedLedgers.isEmpty {
                        ledgerSection(
                            title: "自分が管理する共有家計簿",
                            description: "あなたが作成し、招待リンクを発行できる家計簿です。",
                            ledgers: store.ownedLedgers
                        )
                    }

                    if !store.participatingLedgers.isEmpty {
                        ledgerSection(
                            title: "参加中の共有家計簿",
                            description: "招待リンクから参加した家計簿です。",
                            ledgers: store.participatingLedgers
                        )
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

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "icloud")
                    .font(.footnote)
                    .foregroundStyle(.blue)
                Text("共有家計簿の作成や招待リンクの発行には、iCloudの空き容量が必要です。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                showJoinByLinkSheet = true
            } label: {
                Label("招待リンクで参加", systemImage: "link.badge.plus")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
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

    private func ledgerSection(title: String, description: String, ledgers: [SharedLedger]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(ledgers) { ledger in
                ledgerCard(for: ledger)
            }
        }
    }
    
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
                        Text(store.source(for: ledger) == .shared ? "参加中" : "管理中")
                            .font(.caption2.weight(.semibold))
                            .padding(.vertical, 2)
                            .padding(.horizontal, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(store.source(for: ledger) == .shared ? Color.green.opacity(0.18) : Color.blue.opacity(0.16))
                            )
                    }
                    
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
            
            if store.isOwned(ledger) {
                Button {
                    presentShare(for: ledger)
                } label: {
                    Label("招待・メンバー管理", systemImage: "person.2.badge.plus")
                }
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
        guard store.isOwned(ledger) else {
            shareErrorMessage = "この家計簿のオーナーだけが招待できます。"
            showShareError = true
            return
        }

        shareTargetLedger = ledger
        sharePayload = nil
        shareLoading = true

        Task {
            do {
                let payload = try await store.prepareShare(for: ledger)
                await MainActor.run {
                    self.sharePayload = payload
                    self.shareLoading = false
                }
            } catch {
                await MainActor.run {
                    self.shareErrorMessage = error.localizedDescription
                    self.showShareError = true
                    self.shareLoading = false
                }
            }
        }
    }

    private func handleDelete(_ ledger: SharedLedger) async {
        let success = await store.deleteLedger(ledger)

        if success {
            // 成功メッセージは共有オーバーレイで表示
        } else {
            await MainActor.run {
                deleteErrorMessage = (store.lastError as NSError?)?.localizedDescription
                showDeleteError = true
            }
        }
    }

    private var sharingLoadingView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            VStack(alignment: .leading, spacing: 4) {
                Text("招待の準備中…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("共有リンクを作成しています。数秒お待ちください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

// MARK: - 招待シート

private struct ShareInvitationSheet: View {
    @EnvironmentObject var store: SharedLedgerStore
    let payload: SharedLedgerStore.SharePayload
    let ledger: SharedLedger?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection

                    if let ledger {
                        ledgerSummary(for: ledger)
                    }

                    infoSection

                    VStack(alignment: .leading, spacing: 12) {
                        Text("このリンクを共有すると？")
                            .font(.headline)
                        VStack(alignment: .leading, spacing: 10) {
                            infoRow(icon: "person.crop.circle.badge.plus", text: "受け取った相手が共有メンバーとして参加できます")
                            infoRow(icon: "lock.open.display", text: "参加すると最新の収支やカテゴリがリアルタイムに同期されます")
                            infoRow(icon: "icloud", text: "共有の準備には、iCloudの空き容量が必要です")
                            infoRow(icon: "hand.tap", text: "招待を取り消したい場合は、メンバー管理からいつでも解除できます")
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("招待リンク")
                            .font(.headline)
                        Text("下のボタンから共有オプションを選択してください。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        CloudSharingView(
                            share: payload.share,
                            container: CKContainer.default()
                        )
                        .frame(maxWidth: .infinity)

                        Button {
                            guard let shareURL = payload.share.url else { return }
                            UIPasteboard.general.string = shareURL.absoluteString
                            store.showToast(message: "リンクをコピーしました")
                        } label: {
                            Label("リンクをコピー", systemImage: "doc.on.doc")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(payload.share.url == nil)
//                        .padding(12)
//                        .background(
//                            RoundedRectangle(cornerRadius: 16, style: .continuous)
//                                .fill(Color(.systemBackground))
//                        )
//                        .overlay(
//                            RoundedRectangle(cornerRadius: 16, style: .continuous)
//                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
//                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("共有家計簿を招待")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("リンクを送ってメンバーを招待しましょう")
                .font(.title3.weight(.semibold))
            Text("メッセージやメール、SNSなど好きな方法で共有できます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func ledgerSummary(for ledger: SharedLedger) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 50, height: 50)
                Image(systemName: ledger.icon)
                    .font(.title3)
                    .foregroundStyle(Color.blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(ledger.name)
                    .font(.headline)
                Text("作成日: \(ledger.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("招待の手順")
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                stepRow(number: 1, text: "リンクをコピーまたはAirDropなどで共有する")
                stepRow(number: 2, text: "受け取った相手が開いて参加リクエストを承諾する")
                stepRow(number: 3, text: "メンバーの承認後、共同で家計簿を編集できます")
            }
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .frame(width: 26, height: 26)
                .foregroundStyle(.white)
                .background(
                    Circle().fill(Color.accentColor)
                )
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .frame(width: 24)
                .foregroundStyle(.accent)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}


private struct JoinSharedLedgerByLinkSheet: View {
    @EnvironmentObject var store: SharedLedgerStore
    @Environment(\.dismiss) private var dismiss

    @State private var invitationURLText: String = ""
    @State private var isSubmitting = false
    @State private var validationMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("招待リンクを貼り付け") {
                    TextField("https://www.icloud.com/share/...", text: $invitationURLText, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .keyboardType(.URL)

                    Button("クリップボードから貼り付け") {
                        invitationURLText = UIPasteboard.general.string ?? ""
                    }
                }

                Section("うまく開けないとき") {
                    Text("LINEなどのアプリ内ブラウザでリンクを開くと、参加画面まで進めない場合があります。Safariでリンクを開くか、リンクをコピーしてこの画面から参加してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = validationMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("招待リンクで参加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("参加")
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .overlay {
            if isSubmitting {
                LoadingOverlayView(
                    title: "読み込み中",
                    message: "招待リンクを確認しています…"
                )
            }
        }
    }

    private func submit() {
        let trimmed = invitationURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let host = url.host,
              host.contains("icloud.com")
        else {
            validationMessage = "有効なiCloud共有リンクを入力してください。"
            return
        }

        validationMessage = nil
        isSubmitting = true
        Task {
            let didJoin = await store.acceptShareURL(url)
            await MainActor.run {
                isSubmitting = false
                if didJoin {
                    dismiss()
                }
            }
        }
    }
}


private extension Color {
    static var tertiaryLabel: Color {
        Color(UIColor.tertiaryLabel)
    }
}


struct LoadingOverlayView: View {
    let title: String
    var message: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.accentColor)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 36)
        }
        .transition(.opacity)
    }
}
