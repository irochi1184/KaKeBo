//
//  Views/Components/TransactionPhotoSection.swift
//  KaKeBo
//
//  取引に写真を添付する UI セクション。追加・編集ビュー双方から再利用する。
//  画像実体は PhotoStore（AppGroup 内 Photos/）に保存し、本ビューは
//  ファイル名配列（photoFilenames）のみをバインディングで上書きする。
//

import SwiftUI
import PhotosUI

struct TransactionPhotoSection: View {
    /// 取引に紐づく写真ファイル名（PhotoStore が払い出した実体への参照）
    @Binding var photoFilenames: [String]
    /// テーマのアクセントカラー
    let accent: Color
    /// プレミアム加入中か（写真添付はプレミアム機能）
    let isPremium: Bool
    /// 非プレミアム時に追加操作されたとき（親でペイウォールを出す）
    let onRequirePremium: () -> Void
    /// 添付可能な最大枚数
    var maxPhotos: Int = 5

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var viewerIndex: Int? = nil

    private var canAddMore: Bool { photoFilenames.count < maxPhotos }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            thumbnailRow
        }
        // プレミアム時のみライブラリ選択結果を反映
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importPicked(items) }
        }
        .sheet(isPresented: $showCamera) {
            CameraCaptureView { image in
                addImage(image)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: Binding(
            get: { viewerIndex.map { PhotoViewerItem(index: $0) } },
            set: { viewerIndex = $0?.index }
        )) { item in
            PhotoGalleryView(filenames: photoFilenames, startIndex: item.index)
        }
    }

    // MARK: - ヘッダー / サムネイル列

    private var header: some View {
        HStack {
            Label("写真", systemImage: "photo.on.rectangle.angled")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if !isPremium {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !photoFilenames.isEmpty {
                Text("\(photoFilenames.count)/\(maxPhotos)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var thumbnailRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(photoFilenames.enumerated()), id: \.element) { index, name in
                    thumbnail(name: name, index: index)
                }
                if canAddMore {
                    addButtons
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - サムネイル

    private func thumbnail(name: String, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            PhotoThumbnail(filename: name)
                .frame(width: 76, height: 76)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .onTapGesture { viewerIndex = index }

            Button {
                removePhoto(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
            .offset(x: 6, y: -6)
        }
    }

    // MARK: - 追加ボタン（ライブラリ / カメラ）

    @ViewBuilder
    private var addButtons: some View {
        if isPremium {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: maxPhotos - photoFilenames.count,
                matching: .images,
                photoLibrary: .shared()
            ) {
                addTile(icon: "photo", label: "選択")
            }
            Button {
                showCamera = true
            } label: {
                addTile(icon: "camera", label: "撮影")
            }
        } else {
            // 非プレミアム：タップでペイウォール
            Button(action: onRequirePremium) {
                addTile(icon: "photo", label: "選択")
            }
            Button(action: onRequirePremium) {
                addTile(icon: "camera", label: "撮影")
            }
        }
    }

    private func addTile(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(label)
                .font(.caption2)
        }
        .foregroundStyle(accent)
        .frame(width: 76, height: 76)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accent.opacity(0.30), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    // MARK: - 操作

    private func importPicked(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard photoFilenames.count < maxPhotos else { break }
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data),
               let filename = PhotoStore.shared.save(image) {
                await MainActor.run {
                    photoFilenames.append(filename)
                }
            }
        }
        await MainActor.run { pickerItems = [] }
    }

    private func addImage(_ image: UIImage) {
        guard photoFilenames.count < maxPhotos else { return }
        if let filename = PhotoStore.shared.save(image) {
            photoFilenames.append(filename)
        }
    }

    private func removePhoto(at index: Int) {
        guard photoFilenames.indices.contains(index) else { return }
        // ここではバインディングから外すのみ。実体ファイルの削除は保存時に
        // DataStore 側で旧 photoFilenames と差分を取って行う（キャンセル時の誤削除を防ぐ）。
        photoFilenames.remove(at: index)
    }
}

// MARK: - 全画面ビューア用アイテム（タップした写真のインデックス）

private struct PhotoViewerItem: Identifiable {
    let index: Int
    var id: Int { index }
}

// MARK: - カメラ撮影ブリッジ

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        init(_ parent: CameraCaptureView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
