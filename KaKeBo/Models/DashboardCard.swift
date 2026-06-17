//
//  Models/DashboardCard.swift
//  KaKeBo
//
//  ホーム画面に並ぶカードの種類と、その表示順序の永続化を扱う。
//  ホーム画面（ドラッグ＆ドロップ）と設定画面（並び替えリスト）の
//  両方から参照する共通モデル。
//

import SwiftUI

/// ホーム画面に並ぶカード。並び替えの対象単位。
enum DashboardCard: String, CaseIterable, Identifiable {
    case header         // 月次ヘッダー（収支・支出・収入）
    case budgetAlert    // 予算超過・警告カード
    case forecast       // 支出予測・予算カード
    case weeklySummary  // 週間サマリー
    case donut          // 円グラフ（支出/収入ブレイクダウン）
    case daily          // 日別推移（棒グラフ）
    case transactions   // 最近の取引リスト

    var id: String { rawValue }

    /// 既定の並び順
    static let defaultOrder: [DashboardCard] = [
        .header, .budgetAlert, .forecast, .weeklySummary, .donut, .daily, .transactions
    ]

    /// 設定画面などで表示する名称
    var title: String {
        switch self {
        case .header:        return "今月の収支"
        case .budgetAlert:   return "予算アラート"
        case .forecast:      return "支出予測・予算"
        case .weeklySummary: return "週間サマリー"
        case .donut:         return "カテゴリ別グラフ"
        case .daily:         return "日別の推移"
        case .transactions:  return "最近の取引"
        }
    }

    /// 設定画面などで表示するアイコン（SF Symbols）
    var systemImage: String {
        switch self {
        case .header:        return "yensign.circle"
        case .budgetAlert:   return "exclamationmark.triangle"
        case .forecast:      return "chart.line.uptrend.xyaxis"
        case .weeklySummary: return "calendar.day.timeline.left"
        case .donut:         return "chart.pie"
        case .daily:         return "chart.bar"
        case .transactions:  return "list.bullet"
        }
    }
}

/// AppStorage で順序を保存/復元する（["header","donut",...] という配列文字列で保存）。
struct CardOrderStore {
    @AppStorage("home.cardOrder") private var raw: String = ""

    func load(default order: [DashboardCard] = DashboardCard.defaultOrder) -> [DashboardCard] {
        guard let data = raw.data(using: .utf8),
              let ids = (try? JSONDecoder().decode([String].self, from: data)) else {
            return order
        }
        // 既知のカードだけ復元（将来カード増減しても安全）
        let map = Dictionary(uniqueKeysWithValues: DashboardCard.allCases.map { ($0.id, $0) })
        let seq = ids.compactMap { map[$0] }
        // 足りないカードは末尾に補完
        let missing = DashboardCard.allCases.filter { !seq.contains($0) }
        return seq + missing
    }

    func save(_ order: [DashboardCard]) {
        let ids = order.map(\.id)
        if let data = try? JSONEncoder().encode(ids),
           let s = String(data: data, encoding: .utf8) {
            raw = s
        }
    }
}

/// 非表示にしているカードの集合を AppStorage で保存/復元する。
/// （ここに含まれるカードは、データの有無に関わらずホーム画面に表示しない）
struct HiddenCardStore {
    @AppStorage("home.hiddenCards") private var raw: String = ""

    func load() -> Set<DashboardCard> {
        guard let data = raw.data(using: .utf8),
              let ids = (try? JSONDecoder().decode([String].self, from: data)) else {
            return []
        }
        let map = Dictionary(uniqueKeysWithValues: DashboardCard.allCases.map { ($0.id, $0) })
        return Set(ids.compactMap { map[$0] })
    }

    func save(_ hidden: Set<DashboardCard>) {
        let ids = hidden.map(\.id)
        if let data = try? JSONEncoder().encode(ids),
           let s = String(data: data, encoding: .utf8) {
            raw = s
        }
    }
}
