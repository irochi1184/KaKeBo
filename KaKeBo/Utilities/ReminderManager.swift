//
//  Utilities/ReminderManager.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/22.
//

import Foundation
import UserNotifications

/// アプリ内のローカル通知（リマインダー）を一元管理するユーティリティ。
/// - 基本思想: 「UIからは非同期APIをawaitで呼ぶだけ」にする
/// - 役割:
///   1) 通知の許可取得
///   2) 毎日通知のスケジュール / キャンセル
///   3) “毎月のToDo”起点の単発通知（その月1回）のスケジュール / 掃除
enum ReminderManager {
    
    /// 通知センターの窓口（シングルトン）
    static let center = UNUserNotificationCenter.current()
    
    /// “毎日通知”の固定ID（再スケジュール時の置き換えに使う）
    static let dailyId = "kakebo.daily"
    
    /// 通知の権限を問い合わせる（初回のみシステムUIが出る）
    /// - Returns: 許可されたらtrue。拒否/制限ならfalse。
    /// - Note: completionハンドラ → async/await に橋渡しするため withCheckedContinuation を使用
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            center.requestAuthorization(options: [.alert, .badge, .sound]) { ok, _ in
                // continuation経由でBoolを返す（Voidではないので returning: 必須）
                cont.resume(returning: ok)
            }
        }
    }
    
    /// “毎日通知”のスケジュール（ユーザーが時刻だけを設定する想定）
    /// - Parameters:
    ///   - hour: 通知する時刻(時)
    ///   - minute: 通知する時刻(分)
    /// - Note: ここは雛形。必要なら本文/タイトルや条件（未登録件数がある時だけ etc）を生やす
    static func scheduleDaily(hour: Int, minute: Int) async {
        // 既存の同ID通知を消してから登録（多重登録防止）
        center.removePendingNotificationRequests(withIdentifiers: [dailyId])
        
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        
        let content = UNMutableNotificationContent()
        content.title = "家計簿の記録をお忘れなく"
        content.body = "今日の支出・収入をサクッと登録しましょう。"
        content.sound = .default
        
        // repeats=true の CalendarTrigger → 指定時刻に毎日発火
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let req = UNNotificationRequest(identifier: dailyId, content: content, trigger: trigger)
        
        // add(_:) もCompletionハンドラなのでContinuationでawait化
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            center.add(req) { _ in cont.resume() }
        }
    }
    
    /// “毎月のToDo”テンプレートに紐づく、**その月1回だけ**の通知を登録
    /// - Parameters:
    ///   - template: テンプレ（タイトルなど）
    ///   - due: 当月の期日（例: 2025/10/31）
    ///   - hour: 通知時刻（既定08:00）
    /// - Note:
    ///   IDに (templateID + 年 + 月) を含めることで**同じ月内で上書き**できる
    static func scheduleMonthly(template: RecurringTodoTemplate, due: Date, hour: Int = 8) async {
        let cal = Calendar.current
        let y = cal.component(.year, from: due)
        let m = cal.component(.month, from: due)
        
        // 例: monthly.<UUID>.2025.10 （同一Keyに再登録で置き換え可能）
        let identifier = "monthly.\(template.id.uuidString).\(y).\(m)"
        
        // 同一IDの保留通知があれば削除（多重登録防止）
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        
        // 当月<日>の<8:00>のように、年月日＋時分でスケジュール
        var comps = DateComponents()
        comps.year = y
        comps.month = m
        comps.day = cal.component(.day, from: due)
        comps.hour = hour
        comps.minute = 0
        
        let content = UNMutableNotificationContent()
        content.title = "本日のToDo"
        content.body = "\(template.title)（本日）" // 例: 「家賃の支払い（本日）」
        content.sound = .default
        // 必要なら categoryIdentifier を設定し、通知から「登録へ」ジャンプするアクションも追加可能
        
        // repeats=false なので“単発”通知
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            center.add(req) { _ in cont.resume() }
        }
    }
    
    /// 任意IDの保留通知を削除
    static func cancel(id: String) async {
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }
    
    /// あるテンプレート由来の「当月1回通知」をまとめて掃除（例: テンプレ削除時）
    /// - 仕組み: pending一覧から identifier の接頭辞一致で抽出して削除
    static func cancelAllMonthly(for templateId: UUID) async {
        // pending一覧をawaitで取得
        let pending: [UNNotificationRequest] = await withCheckedContinuation { (cont: CheckedContinuation<[UNNotificationRequest], Never>) in
            center.getPendingNotificationRequests { list in
                cont.resume(returning: list)
            }
        }
        // 例: "monthly.<UUID>." で始まるIDだけを抽出
        let ids = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("monthly.\(templateId.uuidString).") }
        
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
