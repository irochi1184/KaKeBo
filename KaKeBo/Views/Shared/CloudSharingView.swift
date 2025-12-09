//
//  Views/Shared/CloudSharingView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/28.
//

import SwiftUI
import CloudKit
import UIKit

/// CloudKit の UICloudSharingController を SwiftUI から使うためのラッパー
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    
    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.modalPresentationStyle = .formSheet
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // 特に更新処理は不要
    }
}
