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
                        guard let cg = uiImage.cgImage else {
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
            qualityLevel: .balanced,
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

// MARK: - Vision OCR（フォールバック）
fileprivate func recognizeText(from image: CGImage) async throws -> String {
    let request = VNRecognizeTextRequest()
    request.recognitionLanguages = ["ja-JP", "en-US"]
    request.usesLanguageCorrection = true
    request.recognitionLevel = .accurate
    
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    
    let text = request.results?
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
    return text ?? ""
}
