//
//  App/AppDelegate.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import UIKit
import UserNotifications
import CloudKit

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static var pendingShareMetadatas: [CKShare.Metadata] = []
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self

        if let metadata = launchOptions?[.cloudKitShareMetadata] as? CKShare.Metadata {
            Self.enqueueShareMetadata(metadata, notify: false)
        }

        return true
    }
    
    // フォアグラウンドでも通知を見せる
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }
    
    // CloudKit 共有を受け入れたとき（招待リンクなど）
    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Self.enqueueShareMetadata(cloudKitShareMetadata)
    }

    static func drainShareMetadatas() -> [CKShare.Metadata] {
        let current = pendingShareMetadatas
        pendingShareMetadatas.removeAll()
        return current
    }

    private static func enqueueShareMetadata(_ metadata: CKShare.Metadata, notify: Bool = true) {
        pendingShareMetadatas.append(metadata)
        guard notify else { return }
        NotificationCenter.default.post(
            name: .cloudKitShareAccepted,
            object: metadata
        )
    }
}
