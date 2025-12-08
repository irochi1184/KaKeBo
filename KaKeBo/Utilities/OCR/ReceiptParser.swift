//
//  Utilities/OCR/ReceiptParser.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/03.
//

import Foundation

struct ReceiptParseResult {
    var total: Int?
    var date: Date?
    var merchant: String?
    var categoryHint: String?
}

enum ReceiptParser {
    static func parse(_ text: String) -> ReceiptParseResult {
        var result = ReceiptParseResult()
        let lines = text.components(separatedBy: .newlines)
        
        // 1) 日付（最初に出てきた日付っぽいもの）
        if let d = detectDate(in: text) { result.date = d }
        
        // 2) 合計金額候補を抽出し、合計ワード近傍を優先
        let totalHints = ["合計","総計","計","税込","お会計","お買上げ","合算","合計金額"]
        var candidates: [(value: Int, score: Int)] = []
        let moneyRegex = try! NSRegularExpression(pattern: #"(?:(?:¥|￥)?\s?)(\d{1,3}(?:,\d{3})+|\d+)\s?(?:円)?"#)

        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            for m in moneyRegex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let numStr = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
                guard let value = Int(numStr) else { continue }
                // レシートの合計として現実的でない桁数は除外
                guard value > 0, value <= 2_000_000 else { continue }
                var score = 0
                let around = [
                    i > 0 ? lines[i-1] : "",
                    line,
                    i + 1 < lines.count ? lines[i+1] : ""
                ].joined(separator: " ")
                if totalHints.contains(where: { around.contains($0) }) { score += 5 }
                if line.contains("税") { score += 1 }
                // 桁数が多いほどノイズの可能性を下げる
                let digitCount = numStr.count
                if digitCount >= 7 { score -= 2 }
                candidates.append((value, score))
            }
        }
        result.total = candidates.sorted { ($0.score, $0.value) > ($1.score, $1.value) }.first?.value

        // 3) 店名候補（先頭付近のカナ比率の高い行を優先）
        let head = lines.prefix(5)
        result.merchant = head
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .sorted { kanaRatio($0) > kanaRatio($1) }
            .first

        // 4) カテゴリ推定（大まかなキーワードマッチ）
        result.categoryHint = detectCategory(in: text)

        return result
    }
    
    private static func detectDate(in text: String) -> Date? {
        // yyyy/MM/dd, yyyy-MM-dd, Rxx年xx月xx日 等、NSDataDetectorにまず任せる
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let dates = detector?.matches(in: text, options: [], range: range).compactMap { $0.date } ?? []
        return dates.sorted().first
    }
    
    private static func kanaRatio(_ s: String) -> Double {
        let kana = s.unicodeScalars.filter { ("\u{30A0}"..."\u{30FF}").contains($0) }.count
        guard !s.isEmpty else { return 0 }
        return Double(kana) / Double(s.count)
    }

    private static func detectCategory(in text: String) -> String? {
        let lowered = text.lowercased()

        let keywordMap: [String: [String]] = [
            "食費": ["ランチ", "ディナー", "レストラン", "カフェ", "弁当", "食品", "スーパー", "コンビニ", "惣菜"],
            "交通費": ["電車", "バス", "タクシー", "ic", "乗車", "切符", "駅"],
            "水道光熱費": ["電気", "ガス", "水道", "電力", "従量", "基本料金"],
            "通信料": ["wifi", "wi-fi", "通信", "スマホ", "携帯", "インターネット", "データ容量"],
            "医療費": ["薬局", "処方", "調剤", "診療", "病院", "クリニック"],
            "被服費": ["衣料", "服", "アパレル", "ユニクロ", "gu", "ファッション"],
            "住宅費": ["家賃", "賃料", "管理費", "共益費"],
            "交際費": ["ギフト", "贈答", "プレゼント", "お土産", "パーティ"],
            "娯楽費": ["ゲーム", "映画", "ライブ", "カラオケ", "遊戯", "レジャー"],
        ]

        for (category, keywords) in keywordMap {
            if keywords.contains(where: { lowered.contains($0.lowercased()) }) {
                return category
            }
        }
        return nil
    }
}
