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
    /// 内税/外税の小計候補（デバッグ/確認用）
    var subtotal: Int?
    var tax: Int?
}

enum ReceiptParser {
    static func parse(_ text: String) -> ReceiptParseResult {
        var result = ReceiptParseResult()
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // 1) 日付
        result.date = detectDate(in: text, lines: lines)

        // 2) 金額解析（合計・小計・税額）
        let amounts = extractAmounts(lines: lines)
        result.total = amounts.total
        result.subtotal = amounts.subtotal
        result.tax = amounts.tax

        // 3) 店名
        result.merchant = detectMerchant(lines: lines)

        // 4) カテゴリ推定
        result.categoryHint = detectCategory(in: text, merchant: result.merchant)

        return result
    }

    // MARK: - 金額抽出（改良版）

    private struct AmountResult {
        var total: Int?
        var subtotal: Int?
        var tax: Int?
    }

    private static func extractAmounts(lines: [String]) -> AmountResult {
        var result = AmountResult()

        // 合計を示すキーワード（優先度順）
        let totalKeywords = ["合計", "合　計", "総計", "お会計", "お買上", "お買い上げ", "ご請求", "合計金額", "税込合計", "税込計"]
        let subtotalKeywords = ["小計", "小　計", "税抜", "本体"]
        let taxKeywords = ["消費税", "税額", "内税", "外税", "税　"]

        // 金額を抽出する正規表現（複数パターン対応）
        let patterns: [NSRegularExpression] = [
            // ¥1,234 or ￥1234 or ¥ 1,234
            try! NSRegularExpression(pattern: #"[¥￥]\s?(\d{1,3}(?:,\d{3})*|\d+)"#),
            // 1,234円 or 1234円
            try! NSRegularExpression(pattern: #"(\d{1,3}(?:,\d{3})*|\d+)\s?円"#),
            // *1,234 or ＊1,234（レシートで「*」が金額の前に付くパターン）
            try! NSRegularExpression(pattern: #"[*＊]\s?(\d{1,3}(?:,\d{3})*|\d+)"#),
        ]

        struct Candidate {
            let value: Int
            let lineIndex: Int
            let score: Int
            let type: CandidateType
        }

        enum CandidateType { case total, subtotal, tax, unknown }

        var candidates: [Candidate] = []

        for (i, line) in lines.enumerated() {
            // この行から金額を抽出
            let amounts = extractMoneyValues(from: line, patterns: patterns)
            guard !amounts.isEmpty else { continue }

            for amount in amounts {
                guard amount > 0 && amount <= 5_000_000 else { continue }

                var score = 0
                var type: CandidateType = .unknown

                // 前後3行のコンテキストを確認
                let contextRange = max(0, i - 2)...min(lines.count - 1, i + 1)
                let context = lines[contextRange].joined(separator: " ")

                // 合計キーワードチェック
                if totalKeywords.contains(where: { line.contains($0) || context.contains($0) }) {
                    score += 10
                    type = .total
                    // 同じ行にキーワードがある場合はさらに加点
                    if totalKeywords.contains(where: { line.contains($0) }) { score += 5 }
                }

                // 小計キーワード
                if subtotalKeywords.contains(where: { line.contains($0) }) {
                    score += 3
                    type = .subtotal
                }

                // 税額キーワード
                if taxKeywords.contains(where: { line.contains($0) }) {
                    score += 2
                    type = .tax
                }

                // レシート下部に合計が来る傾向（行位置スコア）
                let positionRatio = Double(i) / Double(max(1, lines.count))
                if positionRatio > 0.4 { score += 2 }
                if positionRatio > 0.6 { score += 2 }

                // 「お釣り」「預り」「クレジット」行は合計ではない
                let excludeKeywords = ["お釣", "おつり", "釣銭", "預り", "預かり", "クレジット", "VISA", "MASTER", "カード", "ポイント", "割引後"]
                if excludeKeywords.contains(where: { line.contains($0) }) {
                    score -= 10
                }

                // 桁数による現実性チェック
                if amount < 10 { score -= 5 }  // 10円未満は合計として非現実的

                candidates.append(Candidate(value: amount, lineIndex: i, score: score, type: type))
            }
        }

        // 合計候補の決定
        let totalCandidates = candidates.filter { $0.type == .total }.sorted { $0.score > $1.score }
        if let best = totalCandidates.first {
            result.total = best.value
        } else {
            // 合計キーワードがない場合：最もスコアの高い金額を採用
            let sorted = candidates.filter { $0.type != .tax }.sorted { $0.score > $1.score }
            result.total = sorted.first?.value
        }

        // 小計・税額
        result.subtotal = candidates.filter { $0.type == .subtotal }.max(by: { $0.score < $1.score })?.value
        result.tax = candidates.filter { $0.type == .tax }.max(by: { $0.score < $1.score })?.value

        // 整合性チェック：小計+税≒合計 なら信頼性が高い
        if let sub = result.subtotal, let tax = result.tax, result.total == nil {
            let computed = sub + tax
            if computed > 0 { result.total = computed }
        }

        return result
    }

    private static func extractMoneyValues(from line: String, patterns: [NSRegularExpression]) -> [Int] {
        var values: [Int] = []
        let ns = line as NSString
        for regex in patterns {
            for m in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let numStr = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")
                if let value = Int(numStr) {
                    values.append(value)
                }
            }
        }
        return values
    }

    // MARK: - 日付検出（改良版）

    private static func detectDate(in text: String, lines: [String]) -> Date? {
        // 1) レシート特有のフォーマットを正規表現で先にチェック
        let datePatterns: [(regex: NSRegularExpression, format: String)] = [
            // 2024/01/15 or 2024/1/15
            (try! NSRegularExpression(pattern: #"(20\d{2})[/\-\.](0?[1-9]|1[0-2])[/\-\.](0?[1-9]|[12]\d|3[01])"#), "yyyy/M/d"),
            // 24/01/15 (短縮年)
            (try! NSRegularExpression(pattern: #"(\d{2})[/\-\.](0?[1-9]|1[0-2])[/\-\.](0?[1-9]|[12]\d|3[01])"#), "yy/M/d"),
            // 令和6年1月15日 or R6年1月15日 or R06.01.15
            (try! NSRegularExpression(pattern: #"[令R]\s?0?(\d{1,2})\s?[年\.]\s?(0?[1-9]|1[0-2])\s?[月\.]\s?(0?[1-9]|[12]\d|3[01])"#), "reiwa"),
            // 2024年1月15日
            (try! NSRegularExpression(pattern: #"(20\d{2})\s?年\s?(0?[1-9]|1[0-2])\s?月\s?(0?[1-9]|[12]\d|3[01])\s?日"#), "yyyy年M月d日"),
        ]

        let fullText = lines.joined(separator: " ")
        let ns = fullText as NSString

        for (regex, format) in datePatterns {
            if let m = regex.firstMatch(in: fullText, range: NSRange(location: 0, length: ns.length)) {
                if format == "reiwa" {
                    // 令和→西暦変換
                    let year = Int(ns.substring(with: m.range(at: 1))) ?? 0
                    let month = Int(ns.substring(with: m.range(at: 2))) ?? 0
                    let day = Int(ns.substring(with: m.range(at: 3))) ?? 0
                    let westernYear = 2018 + year
                    var comps = DateComponents()
                    comps.year = westernYear; comps.month = month; comps.day = day
                    if let date = Calendar.current.date(from: comps) { return date }
                } else {
                    let yearStr = ns.substring(with: m.range(at: 1))
                    let monthStr = ns.substring(with: m.range(at: 2))
                    let dayStr = ns.substring(with: m.range(at: 3))
                    var year = Int(yearStr) ?? 0
                    if year < 100 { year += 2000 }
                    let month = Int(monthStr) ?? 0
                    let day = Int(dayStr) ?? 0
                    var comps = DateComponents()
                    comps.year = year; comps.month = month; comps.day = day
                    if let date = Calendar.current.date(from: comps),
                       date <= Date() {
                        return date
                    }
                }
            }
        }

        // 2) フォールバック: NSDataDetector
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let dates = detector?.matches(in: text, options: [], range: range).compactMap { $0.date } ?? []
        // 未来の日付は除外
        return dates.filter { $0 <= Date() }.sorted().last
    }

    // MARK: - 店名検出（改良版）

    private static func detectMerchant(lines: [String]) -> String? {
        // レシートの先頭5行から店名候補を探す
        let headLines = Array(lines.prefix(7))

        // 除外パターン（日付行・電話番号行・住所行等）
        let excludePatterns: [String] = [
            #"^\d{2,4}[/\-\.]"#,           // 日付で始まる
            #"^\d{2,4}年"#,                // 年で始まる
            #"TEL|tel|電話"#,              // 電話番号行
            #"〒|\d{3}-\d{4}"#,            // 郵便番号
            #"^#\d+"#,                     // レシート番号
            #"レジ|レシート|領収"#,          // レシート表示行
            #"^-+$|^=+$|^\*+$"#,          // 区切り線
        ]
        let excludeRegexes = excludePatterns.compactMap { try? NSRegularExpression(pattern: $0) }

        // スコアリング
        struct MerchantCandidate {
            let text: String
            let score: Double
        }

        var candidates: [MerchantCandidate] = []

        for (i, line) in headLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.count >= 2, trimmed.count <= 30 else { continue }

            // 除外パターンに一致したらスキップ
            let nsLine = trimmed as NSString
            let lineRange = NSRange(location: 0, length: nsLine.length)
            if excludeRegexes.contains(where: { $0.firstMatch(in: trimmed, range: lineRange) != nil }) {
                continue
            }

            var score: Double = 0

            // 先頭行ほど店名の可能性が高い
            score += Double(5 - i) * 1.5

            // カタカナ比率が高い = 店名の可能性
            let kRatio = kanaRatio(trimmed)
            score += kRatio * 5.0

            // 全角英数・漢字が混じる = 店名
            let kanjiRatio = cjkRatio(trimmed)
            if kanjiRatio > 0.3 && kanjiRatio < 0.9 { score += 2.0 }

            // 「店」「店舗」が含まれる
            if trimmed.contains("店") || trimmed.contains("支店") || trimmed.contains("本店") {
                score += 3.0
            }

            // 短すぎる行は減点
            if trimmed.count < 3 { score -= 2.0 }

            // 数字だけの行は除外
            if trimmed.allSatisfy({ $0.isNumber || $0 == "-" || $0 == " " }) { continue }

            candidates.append(MerchantCandidate(text: trimmed, score: score))
        }

        return candidates.sorted { $0.score > $1.score }.first?.text
    }

    // MARK: - カテゴリ推定（拡充版）

    private static func detectCategory(in text: String, merchant: String?) -> String? {
        let lowered = (text + " " + (merchant ?? "")).lowercased()

        // 店名辞書（有名チェーン店→カテゴリ）
        let merchantMap: [String: String] = [
            // 食費
            "セブンイレブン": "食費", "ファミリーマート": "食費", "ローソン": "食費",
            "イオン": "食費", "西友": "食費", "ライフ": "食費", "まいばすけっと": "食費",
            "マクドナルド": "食費", "すき家": "食費", "吉野家": "食費", "松屋": "食費",
            "スターバックス": "食費", "ドトール": "食費", "タリーズ": "食費",
            "サイゼリヤ": "食費", "ガスト": "食費", "デニーズ": "食費",
            "ミニストップ": "食費", "デイリーヤマザキ": "食費",
            // 日用品
            "マツモトキヨシ": "日用品費", "ウエルシア": "日用品費", "スギ薬局": "日用品費",
            "ドン・キホーテ": "日用品費", "ダイソー": "日用品費", "セリア": "日用品費",
            "無印良品": "日用品費", "ニトリ": "日用品費",
            // 交通費
            "jr": "交通費", "suica": "交通費", "pasmo": "交通費", "icoca": "交通費",
            // 被服
            "ユニクロ": "被服費", "gu": "被服費", "しまむら": "被服費", "zara": "被服費",
            // 医療
            "薬局": "医療費", "調剤": "医療費",
        ]

        // 店名辞書で一致確認
        for (store, category) in merchantMap {
            if lowered.contains(store.lowercased()) { return category }
        }

        // キーワードマッチ（拡充版）
        let keywordMap: [String: [String]] = [
            "食費": ["ランチ", "ディナー", "レストラン", "カフェ", "弁当", "食品", "スーパー",
                    "コンビニ", "惣菜", "居酒屋", "焼肉", "寿司", "ラーメン", "うどん",
                    "そば", "パン", "ベーカリー", "鮮魚", "精肉", "野菜", "お茶",
                    "コーヒー", "飲料", "菓子", "おにぎり", "サンドイッチ", "デリ",
                    "テイクアウト", "デリバリー", "出前", "フードコート"],
            "日用品費": ["日用品", "洗剤", "シャンプー", "ティッシュ", "トイレットペーパー",
                      "歯ブラシ", "文房具", "電池", "ドラッグストア", "雑貨", "100均"],
            "交通費": ["電車", "バス", "タクシー", "乗車", "切符", "駅", "定期",
                     "回数券", "運賃", "高速", "駐車", "ガソリン", "給油", "燃料"],
            "水道光熱費": ["電気", "ガス", "水道", "電力", "従量", "基本料金",
                        "使用量", "kwh", "東京電力", "関西電力", "大阪ガス", "東京ガス"],
            "通信料": ["wifi", "wi-fi", "通信", "スマホ", "携帯", "インターネット",
                     "データ容量", "回線", "プロバイダ", "ntt", "au", "docomo", "softbank"],
            "医療費": ["薬局", "処方", "調剤", "診療", "病院", "クリニック", "医院",
                     "歯科", "歯医者", "眼科", "皮膚科", "内科", "外科", "整形",
                     "検査", "健診", "保険適用"],
            "被服費": ["衣料", "服", "アパレル", "ファッション", "靴", "バッグ",
                     "アクセサリー", "クリーニング", "洗濯"],
            "住宅費": ["家賃", "賃料", "管理費", "共益費", "更新料", "火災保険"],
            "交際費": ["ギフト", "贈答", "プレゼント", "お土産", "パーティ", "ご祝儀",
                     "香典", "花束", "お中元", "お歳暮"],
            "娯楽費": ["ゲーム", "映画", "ライブ", "カラオケ", "遊戯", "レジャー",
                     "アミューズメント", "テーマパーク", "美術館", "博物館", "本", "書籍",
                     "サブスク", "ジム", "フィットネス", "スポーツ"],
            "教育費": ["学費", "教材", "塾", "予備校", "参考書", "通信教育",
                     "セミナー", "資格", "試験"],
            "美容費": ["美容院", "美容室", "ヘアサロン", "ネイル", "エステ",
                     "化粧品", "コスメ", "スキンケア"],
        ]

        for (category, keywords) in keywordMap {
            if keywords.contains(where: { lowered.contains($0.lowercased()) }) {
                return category
            }
        }
        return nil
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
        let cjk = s.unicodeScalars.filter {
            ("\u{4E00}"..."\u{9FFF}").contains($0)
        }.count
        guard !s.isEmpty else { return 0 }
        return Double(cjk) / Double(s.count)
    }
}
