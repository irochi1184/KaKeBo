//
//  AppRoute.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/02/28.
//

import Foundation

/// アプリ全体のタブ選択やディープリンクを扱うルーター。
final class AppRoute: ObservableObject {
    enum Tab: Hashable {
        case home
        case calendar
        case reports
        case history
        case settings
    }

    @Published var tab: Tab = .home
    @Published private(set) var calendarSelection: Date?

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
            focusCalendar(on: date)
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
