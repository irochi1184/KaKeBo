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
                var score = 0
                let around = [
                    i > 0 ? lines[i-1] : "",
                    line,
                    i + 1 < lines.count ? lines[i+1] : ""
                ].joined(separator: " ")
                if totalHints.contains(where: { around.contains($0) }) { score += 5 }
                if line.contains("税") { score += 1 }
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
}
