//
//  AppRoute.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/02/28.
//

import Foundation
import Combine

/// アプリ全体のタブ選択やディープリンクを扱うルーター。
final class AppRoute: ObservableObject {
    enum Tab: Hashable {
        case home
        case calendar
        case reports
        case history
        case budget
    }

    @Published var tab: Tab = .home
    @Published private(set) var calendarSelection: Date?

    /// 取引追加シートの表示要求（起動時に開く画面の設定・初回選択画面から使用）
    @Published var addTransactionRequested = false

    /// ディープリンクでタブが指定されたか（起動時に開く画面の設定より優先する）
    private(set) var didHandleDeepLink = false

    /// カレンタータブを前面にし、指定日を選択させる。
    func focusCalendar(on date: Date) {
        tab = .calendar
        calendarSelection = date
    }

    /// 受け取ったURLが本アプリ向けであればハンドリングする。
    func handle(url: URL) -> Bool {
        guard url.scheme == "kakebo" else { return false }

        if url.host == "calendar",
           let date = parseDate(from: url) {
            didHandleDeepLink = true
            focusCalendar(on: date)
            return true
        }

        // 予算ウィジェット（ロック画面）タップで予算タブを開く
        if url.host == "budget" {
            didHandleDeepLink = true
            tab = .budget
            return true
        }

        return false
    }

    /// カレンダー選択要求を消費し、二重適用を防ぐ。
    @discardableResult
    func consumeCalendarSelection() -> Date? {
        defer { calendarSelection = nil }
        return calendarSelection
    }

    private func parseDate(from url: URL) -> Date? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let dateString = comps.queryItems?.first(where: { $0.name == "date" })?.value
        else { return nil }

        let f = DateFormatter()
        f.calendar = .current
        f.locale = Locale(identifier: "ja_JP")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: dateString)
    }
}
