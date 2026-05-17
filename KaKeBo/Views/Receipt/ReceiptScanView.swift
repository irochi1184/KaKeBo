//
//  Views/Receipt/ReceiptScanView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import SwiftUI
import Vision
import VisionKit
import PhotosUI
import AVFoundation
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

struct ReceiptScanView: View {
    @Environment(\.dismiss) private var dismiss
    
    let onComplete: (_ recognizedText: String) -> Void
    
    @State private var showPhotoPicker = false
    @State private var recognizedText: String = ""
    @State private var errorMessage: String?
    @State private var showDeniedAlert = false
    @State private var canUseLiveScanner = false
    @State private var checkedPermission = false
    
    var body: some View {
        ZStack {
            // 1) 権限確認中
            if checkedPermission == false {
                ProgressView().task { await preflight() }
                
                // 2) ライブ読み取り（対応端末＆権限OK）
            } else if canUseLiveScanner {
                DataScannerContainer(onTextUpdate: { text in
                    recognizedText = text
                })
                
                // 3) 非対応時：写真から選択のみ
            } else {
                VStack(spacing: 16) {
                    Text("この端末ではライブスキャンが利用できません。写真から読み取ります。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button("写真から選択") { showPhotoPicker = true }
                        .buttonStyle(.borderedProminent)
                }
            }
            
            // 下部アクションバー（常設）
            VStack {
                Spacer()
                HStack(spacing: 12) {
                    Button(role: .cancel) { dismiss() } label: { Text("キャンセル") }
                        .buttonStyle(.bordered)
                    
                    // ★ 追加：「写真から選択」（ライブ対応端末でも常に出す）
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Label("写真から選択", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    // ライブで文字が取れていればそのまま次へ
                    Button {
                        if recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            // まだ何も拾えていない場合は写真選択を促す
                            showPhotoPicker = true
                        } else {
                            onComplete(recognizedText)
                            dismiss()
                        }
                    } label: {
                        Text("この内容で次へ")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .navigationTitle("レシート読み取り")
        // 写真選択（PHPicker）：権限不要
        .sheet(isPresented: $showPhotoPicker) {
            PhotoPickerBridge { uiImage in
                Task {
                    do {
                        guard let cg = preprocessImageForOCR(uiImage) else {
                            errorMessage = "画像の読み込みに失敗しました。"; return
                        }
                        let text = try await recognizeText(from: cg)
                        recognizedText = text
                        onComplete(text)
                        dismiss()
                    } catch { errorMessage = error.localizedDescription }
                }
            }
        }
        // カメラ拒否 → 設定へ誘導 or 写真から選択
        .alert("カメラへのアクセスが許可されていません", isPresented: $showDeniedAlert) {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button("写真から選択") { showPhotoPicker = true }
            Button("閉じる", role: .cancel) { }
        } message: {
            Text("ライブスキャンを使うにはカメラ権限が必要です。")
        }
        // エラーダイアログ
        .alert("読み取りエラー", isPresented: .constant(errorMessage != nil), actions: {
            Button("OK") { errorMessage = nil }
        }, message: { Text(errorMessage ?? "") })
    }
    
    // MARK: - 権限チェック＆可否判定
    private func preflight() async {
        guard DataScannerViewController.isSupported else {
            canUseLiveScanner = false
            checkedPermission = true
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            canUseLiveScanner = DataScannerViewController.isAvailable
            checkedPermission = true
        case .notDetermined:
            let granted = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                AVCaptureDevice.requestAccess(for: .video) { cont.resume(returning: $0) }
            }
            if granted {
                // 許可直後は反映が遅れる場合があるので少し待つ
                try? await Task.sleep(nanoseconds: 200_000_000)
                canUseLiveScanner = DataScannerViewController.isAvailable
            } else {
                canUseLiveScanner = false
                showDeniedAlert = true
            }
            checkedPermission = true
        default:
            canUseLiveScanner = false
            checkedPermission = true
            showDeniedAlert = true
        }
    }
}

// MARK: - DataScanner（ライブOCR）
fileprivate struct DataScannerContainer: UIViewControllerRepresentable {
    let onTextUpdate: (String) -> Void
    
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onTextUpdate: (String) -> Void
        init(onTextUpdate: @escaping (String) -> Void) { self.onTextUpdate = onTextUpdate }
        
        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            onTextUpdate(Self.join(allItems))
        }
        func dataScanner(_ dataScanner: DataScannerViewController,
                         didUpdate updatedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            onTextUpdate(Self.join(allItems))
        }
        private static func join(_ items: [RecognizedItem]) -> String {
            items.compactMap { if case .text(let t) = $0 { return t.transcript } else { return nil } }
                .joined(separator: "\n")
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(onTextUpdate: onTextUpdate) }
    
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}
}

// MARK: - Photo Picker（フォールバック）
fileprivate struct PhotoPickerBridge: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    func makeUIViewController(context: Context) -> some UIViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIViewControllerType, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage) -> Void
        init(onPick: @escaping (UIImage) -> Void) { self.onPick = onPick }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first?.itemProvider,
                  item.canLoadObject(ofClass: UIImage.self) else { return }
            item.loadObject(ofClass: UIImage.self) { obj, _ in
                if let image = obj as? UIImage {
                    DispatchQueue.main.async { self.onPick(image) }
                }
            }
        }
    }
}

// MARK: - Vision OCR（改良版：行位置情報も活用）
fileprivate func recognizeText(from image: CGImage) async throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.usesLanguageCorrection = true
    request.recognitionLevel = .accurate
    request.minimumTextHeight = 0.01  // より小さな文字も検出
    // 複数候補を取得して精度向上
    request.revision = VNRecognizeTextRequestRevision3

    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])

    guard let observations = request.results else { return "" }

    // Y座標（上から下）でソートして自然な読み順に
    let sorted = observations.sorted { obs1, obs2 in
        let y1 = obs1.boundingBox.origin.y
        let y2 = obs2.boundingBox.origin.y
        // Vision座標は左下原点なので y が大きい方が上
        return y1 > y2
    }

    let text = sorted
        .compactMap { observation -> String? in
            // 信頼度が低すぎる候補は除外
            guard let candidate = observation.topCandidates(3).first,
                  candidate.confidence > 0.3 else { return nil }
            return candidate.string
        }
        .joined(separator: "\n")

    return text
}

// MARK: - 画像前処理（改良版：傾き補正 + ノイズ除去 + シャープニング）
fileprivate func preprocessImageForOCR(_ image: UIImage) -> CGImage? {
    guard var ciImage = CIImage(image: image) else { return image.cgImage }

    // 1) 自動方向補正（EXIFに基づく回転修正）
    ciImage = ciImage.oriented(forExifOrientation: Int32(image.imageOrientation.exifValue))

    // 2) グレースケール化（文字認識に不要な色情報を除去）
    let colorControls = CIFilter.colorControls()
    colorControls.inputImage = ciImage
    colorControls.saturation = 0.0
    colorControls.contrast = 1.4       // コントラストを強めに
    colorControls.brightness = 0.05    // わずかに明るく
    ciImage = colorControls.outputImage ?? ciImage

    // 3) シャープニング（文字のエッジを鮮明に）
    let sharpen = CIFilter.sharpenLuminance()
    sharpen.inputImage = ciImage
    sharpen.sharpness = 0.6
    sharpen.radius = 1.5
    ciImage = sharpen.outputImage ?? ciImage

    // 4) ノイズ除去（軽度）
    let noiseReduction = CIFilter.noiseReduction()
    noiseReduction.inputImage = ciImage
    noiseReduction.noiseLevel = 0.01
    noiseReduction.sharpness = 0.5
    ciImage = noiseReduction.outputImage ?? ciImage

    // 5) 露出補正（暗い写真対策）
    let exposure = CIFilter.exposureAdjust()
    exposure.inputImage = ciImage
    exposure.ev = 0.2
    ciImage = exposure.outputImage ?? ciImage

    let context = CIContext(options: [.useSoftwareRenderer: false])
    return context.createCGImage(ciImage, from: ciImage.extent)
}

// UIImageOrientation → EXIF 変換
private extension UIImage.Orientation {
    var exifValue: Int {
        switch self {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }
}
