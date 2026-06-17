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
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        // 過去バージョンで自動登録された ToDo 通知（monthly.*）が
        // ルール未設定でも残って発火するのを防ぐため、起動時に一掃する
        Task { await ReminderManagerV2.purgeLegacyTodoNotifications() }
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
        print("ℹ️ [AppDelegate] userDidAcceptCloudKitShareWith container=\(cloudKitShareMetadata.containerIdentifier)")
        CloudKitShareAcceptanceQueue.shared.enqueue(cloudKitShareMetadata)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable : Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo),
              let subscriptionID = notification.subscriptionID,
              subscriptionID.hasPrefix("kakebo.sharedLedger.")
        else {
            completionHandler(.noData)
            return
        }

        NotificationCenter.default.post(name: .cloudKitDatabaseChanged, object: notification)
        completionHandler(.newData)
    }

    // ユニバーサルリンク経由の共有招待（バックアップで .onOpenURL が呼ばれない環境に備えて冗長に受け取る）
    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard let url = userActivity.webpageURL else { return false }
        print("ℹ️ [AppDelegate] continueUserActivity: \(url.absoluteString)")
        Task {
            do {
                let metadata = try await CKContainer.default().shareMetadata(for: url)
                print("ℹ️ [AppDelegate] shareMetadata resolved (continueUserActivity): container=\(metadata.containerIdentifier)")
                CloudKitShareAcceptanceQueue.shared.enqueue(metadata)
            } catch {
                print("❌ [AppDelegate] shareMetadata error via continueUserActivity for url=\(url.absoluteString): \(error)")
            }
        }
        return true
    }

    // URLスキーム経由の共有招待（SwiftUIの .onOpenURL が拾えない場合のフォールバック）
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
    ) -> Bool {
        print("ℹ️ [AppDelegate] application openURL: \(url.absoluteString)")
        Task {
            do {
                let metadata = try await CKContainer.default().shareMetadata(for: url)
                print("ℹ️ [AppDelegate] shareMetadata resolved (openURL): container=\(metadata.containerIdentifier)")
                CloudKitShareAcceptanceQueue.shared.enqueue(metadata)
            } catch {
                print("❌ [AppDelegate] shareMetadata error via openURL for url=\(url.absoluteString): \(error)")
            }
        }
        return true
    }
}
