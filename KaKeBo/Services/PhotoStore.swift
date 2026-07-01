//
//  Services/PhotoStore.swift
//  KaKeBo
//
//  取引に添付する写真の実体（画像ファイル）を AppGroup コンテナ内で管理するストア。
//  transactions.json には PhotoStore が払い出したファイル名のみを保存し、
//  画像本体はここで読み書きする（JSON 肥大化を避けるため）。
//

import UIKit
import ImageIO

/// 取引添付写真の保存・読込・削除・サムネイル生成を担うサービス。
/// 画像本体は AppGroup コンテナ直下の `Photos/` に `<uuid>.jpg` で保存する。
final class PhotoStore {
    static let shared = PhotoStore()

    /// 保存時の長辺の最大ピクセル数（これより大きい画像は縮小して保存）
    private let maxDimension: CGFloat = 1600
    /// JPEG 圧縮品質
    private let jpegQuality: CGFloat = 0.7
    /// サムネイルの長辺ピクセル数（一覧表示用）
    private let thumbnailMaxPixel: CGFloat = 240

    /// 画像実体を置くディレクトリ（AppGroup 優先、取得不可ならドキュメントディレクトリにフォールバック）
    let photosDirectory: URL

    /// サムネイルのメモリキャッシュ
    private let thumbnailCache = NSCache<NSString, UIImage>()

    private init() {
        let base: URL
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) {
            base = group
        } else {
            base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }
        photosDirectory = base.appendingPathComponent("Photos", isDirectory: true)
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        if !FileManager.default.fileExists(atPath: photosDirectory.path) {
            try? FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        }
    }

    /// ファイル名から画像実体の URL を返す（実在チェックはしない）
    func url(for filename: String) -> URL {
        photosDirectory.appendingPathComponent(filename)
    }

    // MARK: - 保存

    /// 画像を縮小・JPEG 圧縮して保存し、払い出したファイル名を返す。失敗時は nil。
    @discardableResult
    func save(_ image: UIImage) -> String? {
        let resized = downscale(image, maxDimension: maxDimension)
        guard let data = resized.jpegData(compressionQuality: jpegQuality) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let dest = url(for: filename)
        do {
            createDirectoryIfNeeded()
            try data.write(to: dest, options: .atomic)
            return filename
        } catch {
            print("[PhotoStore] 保存失敗: \(error)")
            return nil
        }
    }

    // MARK: - 読込

    /// 原寸（保存サイズ）の画像を読み込む。
    func loadImage(_ filename: String) -> UIImage? {
        UIImage(contentsOfFile: url(for: filename).path)
    }

    /// 一覧表示用のサムネイルを返す（メモリ効率のため ImageIO でダウンサンプリングし、結果をキャッシュ）。
    func loadThumbnail(_ filename: String) -> UIImage? {
        if let cached = thumbnailCache.object(forKey: filename as NSString) {
            return cached
        }
        let fileURL = url(for: filename)
        guard let thumb = Self.downsampledImage(at: fileURL, maxPixel: thumbnailMaxPixel) else {
            return nil
        }
        thumbnailCache.setObject(thumb, forKey: filename as NSString)
        return thumb
    }

    // MARK: - 削除

    /// 指定ファイル名の画像実体とサムネイルキャッシュを削除する。
    func delete(_ filenames: [String]) {
        for name in filenames {
            try? FileManager.default.removeItem(at: url(for: name))
            thumbnailCache.removeObject(forKey: name as NSString)
        }
    }

    /// transactions に存在しないファイル名の画像（孤児ファイル）を一括削除する。
    /// 取引削除のたびに個別削除しているが、念のためのクリーンアップ用。
    func purgeOrphans(keeping referenced: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: photosDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for file in files {
            let name = file.lastPathComponent
            if !referenced.contains(name) {
                try? FileManager.default.removeItem(at: file)
                thumbnailCache.removeObject(forKey: name as NSString)
            }
        }
    }

    // MARK: - ヘルパー

    /// 長辺が maxDimension を超える場合のみ縮小（超えなければ元画像をそのまま返す）。
    private func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longSide = max(image.size.width, image.size.height)
        guard longSide > maxDimension else { return image }
        let scale = maxDimension / longSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// ImageIO でファイルから直接ダウンサンプリングしたサムネイルを生成する（フル展開しないので省メモリ）。
    private static func downsampledImage(at url: URL, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
