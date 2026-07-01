//
//  Views/Components/PhotoGalleryView.swift
//  KaKeBo
//
//  取引写真の表示に関する再利用コンポーネント群。
//  - PhotoThumbnail: ファイル名から非同期にサムネイルを読み込む小ビュー
//  - PhotoGalleryView: 複数写真を全画面でページ送り表示するビューア
//  - TransactionRowPhotoPreview: 一覧行に置く小さなプレビュー（タップでギャラリーを開く）
//

import SwiftUI

// MARK: - サムネイル（非同期読込）

/// PhotoStore のサムネイルを読み込んで表示する。読み込み中はプレースホルダ。
struct PhotoThumbnail: View {
    let filename: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay(
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .task(id: filename) {
            if image == nil {
                let loaded = PhotoStore.shared.loadThumbnail(filename)
                await MainActor.run { image = loaded }
            }
        }
    }
}

// MARK: - 全画面ギャラリー（複数枚ページ送り）

/// 写真を全画面でページ送り表示するビューア。任意の開始インデックス指定可。
struct PhotoGalleryView: View {
    let filenames: [String]
    var startIndex: Int = 0

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selection) {
                ForEach(Array(filenames.enumerated()), id: \.offset) { index, name in
                    FullImage(filename: name)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: filenames.count > 1 ? .automatic : .never))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            VStack {
                HStack {
                    if filenames.count > 1 {
                        Text("\(selection + 1) / \(filenames.count)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.2)))
                            .padding(.leading)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.white.opacity(0.25))
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onAppear { selection = min(max(startIndex, 0), max(filenames.count - 1, 0)) }
    }

    /// 1枚分の原寸画像（非同期読込）
    private struct FullImage: View {
        let filename: String
        @State private var image: UIImage?

        var body: some View {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .task(id: filename) {
                let loaded = PhotoStore.shared.loadImage(filename)
                await MainActor.run { image = loaded }
            }
        }
    }
}

// MARK: - 一覧行用プレビュー

/// 一覧の行に置く小さな写真プレビュー。行の高さを変えないよう固定サイズ。
/// タップで全画面ギャラリーを開く。行全体がボタンのケースでも誤遷移しないよう
/// highPriorityGesture でタップを横取りする。
struct TransactionRowPhotoPreview: View {
    let filenames: [String]
    /// プレビューの一辺サイズ（行の高さに収まる値を渡す）
    var size: CGFloat = 34

    @State private var showGallery = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PhotoThumbnail(filename: filenames.first ?? "")
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                )

            // 複数枚あるときは枚数バッジ
            if filenames.count > 1 {
                Text("\(filenames.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.6)))
                    .offset(x: 4, y: -4)
            }
        }
        .contentShape(Rectangle())
        .highPriorityGesture(
            TapGesture().onEnded { showGallery = true }
        )
        .fullScreenCover(isPresented: $showGallery) {
            PhotoGalleryView(filenames: filenames)
        }
        .accessibilityLabel("添付写真 \(filenames.count)枚を表示")
    }
}
