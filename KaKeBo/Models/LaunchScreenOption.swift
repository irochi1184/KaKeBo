//
//  Models/LaunchScreenOption.swift
//  KaKeBo
//
//  アプリ起動時に最初に表示する画面の設定
//

import Foundation

/// アプリ起動時に最初に表示する画面の選択肢
enum LaunchScreenOption: String, CaseIterable, Identifiable, Codable {
    case home
    case calendar
    case reports
    case history
    case budget
    case addTransaction

    var id: String { rawValue }

    /// UserDefaults(AppGroup) の保存キー
    static let storageKey = "launch.screen"
    /// 初回の選択画面（機能紹介）を表示済みかどうかのキー
    static let promptShownKey = "launch.screen.promptShown"

    var title: String {
        switch self {
        case .home: return "ホーム"
        case .calendar: return "カレンダー"
        case .reports: return "レポート"
        case .history: return "取引一覧"
        case .budget: return "予算"
        case .addTransaction: return "取引追加"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "今月の収支やカードをまとめて確認"
        case .calendar: return "日ごとの記録をカレンダーで確認"
        case .reports: return "グラフで支出の傾向を分析"
        case .history: return "履歴タブで取引を一覧・検索"
        case .budget: return "カテゴリ別予算の残りを確認"
        case .addTransaction: return "起動してすぐに取引を入力"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .reports: return "chart.pie.fill"
        case .history: return "magnifyingglass"
        case .budget: return "yensign.circle"
        case .addTransaction: return "plus.circle.fill"
        }
    }

    /// 対応するタブ（取引追加はホームタブの上に入力シートを重ねる）
    var tab: AppRoute.Tab {
        switch self {
        case .home, .addTransaction: return .home
        case .calendar: return .calendar
        case .reports: return .reports
        case .history: return .history
        case .budget: return .budget
        }
    }

    /// 保存済みの設定を読み込む（未設定はホーム）
    static func loadFromDefaults() -> LaunchScreenOption {
        guard let raw = UserDefaults.appGroup.string(forKey: storageKey),
              let option = LaunchScreenOption(rawValue: raw)
        else { return .home }
        return option
    }
}
