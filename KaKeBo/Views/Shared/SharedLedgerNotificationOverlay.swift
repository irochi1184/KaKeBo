//
//  Views/Shared/SharedLedgerNotificationOverlay.swift
//  KaKeBo
//
//  Created by ChatGPT on 2025/11/25.
//

import SwiftUI

struct SharedLedgerNotificationOverlay: View {
    @EnvironmentObject var store: SharedLedgerStore

    var body: some View {
        VStack(spacing: 10) {
            if store.isAcceptingShare {
                shareAcceptanceProgressView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let copy = store.activeCopy {
                copyProgressView(copy: copy)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let toast = store.globalToast {
                toastView(toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: store.isAcceptingShare)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: store.activeCopy != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: store.globalToast)
    }


    private var shareAcceptanceProgressView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("共有家計簿へ参加中…")
                .font(.caption.weight(.semibold))
            Spacer()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground).opacity(0.95))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
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
                .fill(Color(.systemBackground).opacity(0.95))
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private func toastView(_ toast: SharedLedgerStore.ToastState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: toast.systemImage)
                .foregroundStyle(toast.systemImage.contains("triangle") ? .orange : .green)
            VStack(alignment: .leading, spacing: 6) {
                Text(toast.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let actionTitle = toast.actionTitle, let action = toast.action {
                    Button(actionTitle) {
                        action()
                    }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                }
            }
            Spacer()
            Button {
                withAnimation {
                    store.globalToast = nil
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
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
