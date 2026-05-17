//
//  Utilities/OCR/PaymentScreenshotParser.swift
//  KaKeBo
//
//  Created by Claude on 2026/05/18.
//

import Foundation

/// 決済アプリ（PayPay, LINE Pay, 楽天Pay等）のスクリーンショットから取引情報を抽出する
enum PaymentScreenshotParser {

    /// 決済アプリの種類
    enum PaymentApp: String {
        case paypay = "PayPay"
        case linePay = "LINE Pay"
        case rakutenPay = "楽天ペイ"
        case dBarai = "d払い"
        case auPay = "au PAY"
        case merpay = "メルペイ"
        case unknown = "不明"
    }

    /// 解析結果
    struct PaymentResult {
        var amount: Int?
        var date: Date?
        var merchant: String?
        var categoryHint: String?
        var app: PaymentApp = .unknown
        var paymentMethod: String?  // 「PayPay残高」「クレジットカード」等
        var pointsUsed: Int?        // ポイント利用額
    }

    /// テキストから決済アプリのスクリーンショットかどうかを判定し、パースする
    static func parse(_ text: String) -> PaymentResult? {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // どのアプリか判定
        let app = detectApp(lines: lines, fullText: text)
        guard app != .unknown else { return nil }

        var result = PaymentResult()
        result.app = app

        switch app {
        case .paypay:
            parsePayPay(lines: lines, fullText: text, result: &result)
        case .linePay:
            parseLinePay(lines: lines, fullText: text, result: &result)
        case .rakutenPay:
            parseRakutenPay(lines: lines, fullText: text, result: &result)
        case .dBarai:
            parseDBatai(lines: lines, fullText: text, result: &result)
        case .auPay:
            parseAuPay(lines: lines, fullText: text, result: &result)
        case .merpay:
            parseMerpay(lines: lines, fullText: text, result: &result)
        case .unknown:
            return nil
        }

        // カテゴリ推定（店名ベース）
        if result.categoryHint == nil, let merchant = result.merchant {
            result.categoryHint = ReceiptParser.parse(merchant).categoryHint
        }

        return result
    }

    /// 通常のレシートパーサーか決済スクショパーサーかを自動判定してパースする
    static func smartParse(_ text: String) -> ReceiptParseResult {
        // まず決済アプリのスクリーンショットか判定
        if let paymentResult = parse(text) {
            // PaymentResult → ReceiptParseResult に変換
            var receipt = ReceiptParseResult()
            receipt.total = paymentResult.amount
            receipt.date = paymentResult.date
            receipt.merchant = paymentResult.merchant
            receipt.categoryHint = paymentResult.categoryHint
            return receipt
        }
        // 通常のレシートとしてパース
        return ReceiptParser.parse(text)
    }

    // MARK: - アプリ判定

    private static func detectApp(lines: [String], fullText: String) -> PaymentApp {
        let text = fullText.lowercased()
        let joinedLines = lines.joined(separator: " ")

        // PayPay
        if text.contains("paypay") || joinedLines.contains("PayPay") ||
            text.contains("ペイペイ") || text.contains("支払い完了") && text.contains("残高") {
            return .paypay
        }

        // LINE Pay
        if text.contains("line pay") || text.contains("linepay") ||
            (text.contains("line") && text.contains("支払い")) {
            return .linePay
        }

        // 楽天ペイ
        if text.contains("楽天ペイ") || text.contains("rakuten pay") ||
            text.contains("r pay") || (text.contains("楽天") && text.contains("支払い")) {
            return .rakutenPay
        }

        // d払い
        if text.contains("d払い") || text.contains("d-barai") ||
            (text.contains("dポイント") && text.contains("支払")) {
            return .dBarai
        }

        // au PAY
        if text.contains("au pay") || text.contains("aupay") ||
            (text.contains("au") && text.contains("pay")) {
            return .auPay
        }

        // メルペイ
        if text.contains("メルペイ") || text.contains("merpay") ||
            (text.contains("メルカリ") && text.contains("支払")) {
            return .merpay
        }

        return .unknown
    }

    // MARK: - PayPay パーサー

    private static func parsePayPay(lines: [String], fullText: String, result: inout PaymentResult) {
        // PayPayの支払い完了画面:
        // - 大きな金額表示（¥1,234 or -1,234円）
        // - 店名
        // - 日時
        // - 支払い方法（PayPay残高 / クレジットカード等）

        // 金額: PayPayは支払い完了時に大きく金額を表示する
        result.amount = extractPaymentAmount(lines: lines, fullText: fullText)

        // 店名: 「支払い先」や金額の近くにある店名
        result.merchant = extractPayPayMerchant(lines: lines)

        // 日時
        result.date = extractPaymentDate(lines: lines, fullText: fullText)

        // 支払い方法
        if fullText.contains("PayPay残高") { result.paymentMethod = "PayPay残高" }
        else if fullText.contains("クレジット") { result.paymentMethod = "クレジットカード" }
        else if fullText.contains("あと払い") { result.paymentMethod = "PayPayあと払い" }

        // ポイント利用
        result.pointsUsed = extractPoints(lines: lines, keywords: ["ポイント利用", "PayPayポイント"])
    }

    // MARK: - LINE Pay パーサー

    private static func parseLinePay(lines: [String], fullText: String, result: inout PaymentResult) {
        result.amount = extractPaymentAmount(lines: lines, fullText: fullText)
        result.merchant = extractGenericMerchant(lines: lines, appKeywords: ["LINE Pay", "LINE", "送金", "決済"])
        result.date = extractPaymentDate(lines: lines, fullText: fullText)
        if fullText.contains("LINE Pay残高") { result.paymentMethod = "LINE Pay残高" }
    }

    // MARK: - 楽天ペイ パーサー

    private static func parseRakutenPay(lines: [String], fullText: String, result: inout PaymentResult) {
        result.amount = extractPaymentAmount(lines: lines, fullText: fullText)
        result.merchant = extractGenericMerchant(lines: lines, appKeywords: ["楽天ペイ", "楽天", "Rakuten", "R Pay"])
        result.date = extractPaymentDate(lines: lines, fullText: fullText)
        result.pointsUsed = extractPoints(lines: lines, keywords: ["ポイント利用", "楽天ポイント"])
        if fullText.contains("楽天キャッシュ") { result.paymentMethod = "楽天キャッシュ" }
    }

    // MARK: - d払い パーサー

    private static func parseDBatai(lines: [String], fullText: String, result: inout PaymentResult) {
        result.amount = extractPaymentAmount(lines: lines, fullText: fullText)
        result.merchant = extractGenericMerchant(lines: lines, appKeywords: ["d払い", "d-barai", "dポイント"])
        result.date = extractPaymentDate(lines: lines, fullText: fullText)
        result.pointsUsed = extractPoints(lines: lines, keywords: ["dポイント利用", "ポイント充当"])
        if fullText.contains("電話料金合算") { result.paymentMethod = "電話料金合算" }
    }

    // MARK: - au PAY パーサー

    private static func parseAuPay(lines: [String], fullText: String, result: inout PaymentResult) {
        result.amount = extractPaymentAmount(lines: lines, fullText: fullText)
        result.merchant = extractGenericMerchant(lines: lines, appKeywords: ["au PAY", "au", "Ponta"])
        result.date = extractPaymentDate(lines: lines, fullText: fullText)
        result.pointsUsed = extractPoints(lines: lines, keywords: ["Pontaポイント", "ポイント利用"])
    }

    // MARK: - メルペイ パーサー

    private static func parseMerpay(lines: [String], fullText: String, result: inout PaymentResult) {
        result.amount = extractPaymentAmount(lines: lines, fullText: fullText)
        result.merchant = extractGenericMerchant(lines: lines, appKeywords: ["メルペイ", "メルカリ", "merpay"])
        result.date = extractPaymentDate(lines: lines, fullText: fullText)
        result.pointsUsed = extractPoints(lines: lines, keywords: ["ポイント利用", "メルカリポイント"])
    }

    // MARK: - 共通抽出メソッド

    /// 決済金額を抽出する（決済アプリ特有の大きな金額表示に対応）
    private static func extractPaymentAmount(lines: [String], fullText: String) -> Int? {
        // 決済アプリの金額表示パターン
        let patterns: [NSRegularExpression] = [
            // -¥1,234 or ¥1,234 or -￥1,234（支払い金額、マイナス付き）
            try! NSRegularExpression(pattern: #"-?\s?[¥￥]\s?(\d{1,3}(?:,\d{3})*|\d+)"#),
            // 1,234円 or 1234円
            try! NSRegularExpression(pattern: #"(\d{1,3}(?:,\d{3})*|\d+)\s?円"#),
            // 支払金額 1,234 or 合計 1,234
            try! NSRegularExpression(pattern: #"(?:支払|合計|お支払い|決済).*?(\d{1,3}(?:,\d{3})*|\d+)"#),
        ]

        struct Candidate {
            let value: Int
            let score: Int
        }

        var candidates: [Candidate] = []

        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            for regex in patterns {
                for m in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                    let numStr = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
                    guard let value = Int(numStr), value > 0, value <= 10_000_000 else { continue }

                    var score = 0

                    // 「支払い」「合計」キーワードが近い行にある
                    let context = lines[max(0, i-1)...min(lines.count-1, i+1)].joined(separator: " ")
                    if context.contains("支払") || context.contains("合計") || context.contains("決済") {
                        score += 10
                    }

                    // 「お釣り」「残高」「チャージ」「ポイント獲得」は金額ではない
                    let excludes = ["お釣り", "残高", "チャージ", "ポイント獲得", "還元", "付与", "キャッシュバック"]
                    if excludes.contains(where: { line.contains($0) }) {
                        score -= 20
                    }

                    // ¥記号付きは決済金額の可能性が高い
                    if line.contains("¥") || line.contains("￥") { score += 3 }

                    // 金額として現実的な範囲
                    if value >= 100 && value <= 100_000 { score += 2 }

                    candidates.append(Candidate(value: value, score: score))
                }
            }
        }

        return candidates.sorted { $0.score > $1.score }.first?.value
    }

    /// PayPay特有の店名抽出
    private static func extractPayPayMerchant(lines: [String]) -> String? {
        // PayPayの支払い完了画面では店名が独立した行で表示される
        // 「支払い先」ラベルの後の行、または金額行の前後

        // 「支払い先」パターン
        for (i, line) in lines.enumerated() {
            if line.contains("支払い先") || line.contains("お支払い先") {
                // 次の行が店名
                if i + 1 < lines.count {
                    let next = lines[i + 1]
                    if isLikelyStoreName(next) { return next }
                }
            }
        }

        // 一般的な店名検出にフォールバック
        return extractGenericMerchant(lines: lines, appKeywords: ["PayPay", "支払い完了", "残高"])
    }

    /// 汎用店名抽出（アプリ固有キーワードを除外して探す）
    private static func extractGenericMerchant(lines: [String], appKeywords: [String]) -> String? {
        // 除外すべきパターン
        let excludePatterns: [String] = [
            "支払い", "完了", "残高", "ポイント", "合計", "日時", "決済",
            "利用", "履歴", "取消", "チャージ", "送金", "クーポン",
            "キャンペーン", "おトク", "還元"
        ] + appKeywords

        let datePattern = try! NSRegularExpression(pattern: #"\d{4}[/\-\.]\d{1,2}[/\-\.]\d{1,2}"#)
        let timePattern = try! NSRegularExpression(pattern: #"\d{1,2}:\d{2}"#)
        let amountPattern = try! NSRegularExpression(pattern: #"[¥￥]\s?\d+|^\d+円$"#)

        struct Candidate {
            let text: String
            let score: Double
        }

        var candidates: [Candidate] = []

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2, trimmed.count <= 25 else { continue }

            // 除外チェック
            if excludePatterns.contains(where: { trimmed.contains($0) }) { continue }

            let ns = trimmed as NSString
            let range = NSRange(location: 0, length: ns.length)

            // 日付行・時刻行・金額行は除外
            if datePattern.firstMatch(in: trimmed, range: range) != nil { continue }
            if timePattern.firstMatch(in: trimmed, range: range) != nil && trimmed.count < 10 { continue }
            if amountPattern.firstMatch(in: trimmed, range: range) != nil { continue }

            // 数字だけの行は除外
            if trimmed.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " || $0 == "," }) { continue }

            var score: Double = 0

            // 位置スコア（中央付近に店名が来ることが多い）
            let posRatio = Double(i) / Double(max(1, lines.count))
            if posRatio > 0.2 && posRatio < 0.6 { score += 3.0 }

            // カタカナ・漢字比率
            let kana = kanaRatio(trimmed)
            let kanji = cjkRatio(trimmed)
            if kana > 0.3 || kanji > 0.3 { score += 2.0 }

            // 「店」「支店」を含む
            if trimmed.contains("店") { score += 3.0 }

            // 短すぎは減点
            if trimmed.count < 3 { score -= 1.0 }

            candidates.append(Candidate(text: trimmed, score: score))
        }

        return candidates.sorted { $0.score > $1.score }.first?.text
    }

    /// 日時を抽出する
    private static func extractPaymentDate(lines: [String], fullText: String) -> Date? {
        let joinedLines = lines.joined(separator: " ")

        // 決済アプリ特有の日時フォーマット
        let patterns: [(regex: NSRegularExpression, hasTime: Bool)] = [
            // 2024/01/15 14:30 or 2024-01-15 14:30
            (try! NSRegularExpression(pattern: #"(20\d{2})[/\-\.](0?[1-9]|1[0-2])[/\-\.](0?[1-9]|[12]\d|3[01])\s+(\d{1,2}):(\d{2})"#), true),
            // 2024年1月15日 14:30
            (try! NSRegularExpression(pattern: #"(20\d{2})\s?年\s?(0?[1-9]|1[0-2])\s?月\s?(0?[1-9]|[12]\d|3[01])\s?日\s*(\d{1,2}):(\d{2})"#), true),
            // 1/15 14:30（年なし、今年とみなす）
            (try! NSRegularExpression(pattern: #"(0?[1-9]|1[0-2])[/\-\.](0?[1-9]|[12]\d|3[01])\s+(\d{1,2}):(\d{2})"#), true),
            // 2024/01/15（時刻なし）
            (try! NSRegularExpression(pattern: #"(20\d{2})[/\-\.](0?[1-9]|1[0-2])[/\-\.](0?[1-9]|[12]\d|3[01])"#), false),
        ]

        let ns = joinedLines as NSString
        let range = NSRange(location: 0, length: ns.length)

        for (regex, hasTime) in patterns {
            if let m = regex.firstMatch(in: joinedLines, range: range) {
                var comps = DateComponents()
                let cal = Calendar.current

                if hasTime && m.numberOfRanges >= 6 {
                    // フルフォーマット（年月日時分）
                    let g1 = ns.substring(with: m.range(at: 1))
                    let g2 = ns.substring(with: m.range(at: 2))
                    let g3 = ns.substring(with: m.range(at: 3))
                    let g4 = ns.substring(with: m.range(at: 4))
                    let g5 = ns.substring(with: m.range(at: 5))
                    comps.year = Int(g1); comps.month = Int(g2); comps.day = Int(g3)
                    comps.hour = Int(g4); comps.minute = Int(g5)
                } else if hasTime && m.numberOfRanges == 5 {
                    // 年なし（M/d HH:mm）
                    let g1 = ns.substring(with: m.range(at: 1))
                    let g2 = ns.substring(with: m.range(at: 2))
                    let g3 = ns.substring(with: m.range(at: 3))
                    let g4 = ns.substring(with: m.range(at: 4))
                    comps.year = cal.component(.year, from: Date())
                    comps.month = Int(g1); comps.day = Int(g2)
                    comps.hour = Int(g3); comps.minute = Int(g4)
                } else {
                    // 年月日のみ
                    let g1 = ns.substring(with: m.range(at: 1))
                    let g2 = ns.substring(with: m.range(at: 2))
                    let g3 = ns.substring(with: m.range(at: 3))
                    comps.year = Int(g1); comps.month = Int(g2); comps.day = Int(g3)
                }

                if let date = cal.date(from: comps), date <= Date() {
                    return date
                }
            }
        }

        return nil
    }

    /// ポイント利用額を抽出する
    private static func extractPoints(lines: [String], keywords: [String]) -> Int? {
        let amountRegex = try! NSRegularExpression(pattern: #"(\d{1,3}(?:,\d{3})*|\d+)\s?(?:pt|ポイント|P|円相当)"#)

        for (i, line) in lines.enumerated() {
            let context = ([i > 0 ? lines[i-1] : "", line]).joined(separator: " ")
            guard keywords.contains(where: { context.contains($0) }) else { continue }

            let ns = line as NSString
            if let m = amountRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                let numStr = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
                return Int(numStr)
            }
        }
        return nil
    }

    /// 店名らしい行かどうか判定
    private static func isLikelyStoreName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.count <= 25 else { return false }
        // 数字だけや記号だけの行は除外
        if trimmed.allSatisfy({ $0.isNumber || $0.isPunctuation || $0 == " " }) { return false }
        return true
    }

    // MARK: - ユーティリティ

    private static func kanaRatio(_ s: String) -> Double {
        let kana = s.unicodeScalars.filter {
            ("\u{30A0}"..."\u{30FF}").contains($0) || ("\u{3040}"..."\u{309F}").contains($0)
        }.count
        guard !s.isEmpty else { return 0 }
        return Double(kana) / Double(s.count)
    }

    private static func cjkRatio(_ s: String) -> Double {
        let cjk = s.unicodeScalars.filter { ("\u{4E00}"..."\u{9FFF}").contains($0) }.count
        guard !s.isEmpty else { return 0 }
        return Double(cjk) / Double(s.count)
    }
}
