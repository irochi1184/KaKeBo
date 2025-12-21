import Foundation

struct EmailReceiptImportService {
    enum Source: String {
        case rakutenPay = "楽天Pay"
        case jcb = "JCBカード"
    }

    struct ParsedReceipt: Hashable {
        let source: Source
        let date: Date
        let amount: Int
        let merchant: String?
        let memo: String
    }

    struct ImportResult {
        let inserted: Int
        let skipped: Int
        let message: String
    }

    enum ImportError: LocalizedError {
        case senderNotRegistered
        case noReceiptsFound
        case amountNotFound

        var errorDescription: String? {
            switch self {
            case .senderNotRegistered:
                return "登録済みのメールアドレスと一致しません。"
            case .noReceiptsFound:
                return "通知メールとして解析できる内容が見つかりませんでした。"
            case .amountNotFound:
                return "金額が見つかりませんでした。"
            }
        }
    }

    func importReceipts(
        text: String,
        senderInput: String?,
        store: DataStore,
        settings: EmailImportSettings,
        now: Date = Date()
    ) throws -> ImportResult {
        let parsed = try parseReceipts(text: text, senderInput: senderInput, settings: settings, now: now)
        guard !parsed.isEmpty else {
            throw ImportError.noReceiptsFound
        }

        var inserted = 0
        var skipped = 0
        for receipt in parsed {
            guard let categoryId = categoryId(for: receipt.source, settings: settings, store: store) else {
                skipped += 1
                continue
            }
            if isDuplicate(receipt, in: store.transactions) {
                skipped += 1
                continue
            }
            let tx = Transaction(
                date: receipt.date,
                amount: receipt.amount,
                type: .expense,
                memo: receipt.memo,
                categoryId: categoryId,
                tags: ["メール通知", receipt.source.rawValue]
            )
            store.addTransaction(tx)
            inserted += 1
        }

        let message = "取込 \(inserted) 件 / スキップ \(skipped) 件"
        return ImportResult(inserted: inserted, skipped: skipped, message: message)
    }

    func parseReceipts(
        text: String,
        senderInput: String?,
        settings: EmailImportSettings,
        now: Date = Date()
    ) throws -> [ParsedReceipt] {
        let sender = extractSender(from: text, fallback: senderInput)
        guard let source = identifySource(sender: sender, text: text, settings: settings) else {
            throw ImportError.senderNotRegistered
        }

        let blocks = splitByReceiptMarkers(text)
        let candidates = blocks.isEmpty ? [text] : blocks

        var receipts: [ParsedReceipt] = []
        for block in candidates {
            if let receipt = parseReceipt(from: block, source: source, now: now) {
                receipts.append(receipt)
            }
        }

        if receipts.isEmpty {
            if let receipt = parseReceipt(from: text, source: source, now: now) {
                receipts.append(receipt)
            }
        }

        if receipts.isEmpty {
            throw ImportError.noReceiptsFound
        }
        return receipts
    }

    private func identifySource(sender: String?, text: String, settings: EmailImportSettings) -> Source? {
        let normalizedSender = normalize(sender ?? "")
        if !settings.rakutenPaySender.isEmpty,
           normalizedSender.contains(normalize(settings.rakutenPaySender)) {
            return .rakutenPay
        }
        if !settings.jcbSender.isEmpty,
           normalizedSender.contains(normalize(settings.jcbSender)) {
            return .jcb
        }

        let lowered = text.lowercased()
        if lowered.contains("楽天") || lowered.contains("rakuten") {
            return .rakutenPay
        }
        if lowered.contains("jcb") {
            return .jcb
        }
        return nil
    }

    private func extractSender(from text: String, fallback: String?) -> String? {
        let pattern = #"(?mi)^(from|差出人|送信元)[:：]\s*(.+)$"#
        if let match = text.firstMatch(pattern: pattern), match.count > 2 {
            return match[2]
        }
        if let fallback, !fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return fallback
        }
        return nil
    }

    private func splitByReceiptMarkers(_ text: String) -> [String] {
        let markers = [
            "----- Forwarded message -----",
            "-----Original Message-----",
            "----- Original Message -----"
        ]
        var blocks: [String] = []
        var current = text
        for marker in markers where text.contains(marker) {
            let parts = current.components(separatedBy: marker)
            blocks.append(contentsOf: parts)
            current = ""
        }
        if blocks.isEmpty {
            return []
        }
        return blocks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func parseReceipt(from text: String, source: Source, now: Date) -> ParsedReceipt? {
        guard let amount = extractAmount(from: text) else { return nil }
        let date = extractDate(from: text, now: now) ?? now
        let merchant = extractMerchant(from: text)
        let memo = buildMemo(source: source, merchant: merchant)
        return ParsedReceipt(source: source, date: date, amount: amount, merchant: merchant, memo: memo)
    }

    private func extractAmount(from text: String) -> Int? {
        let patterns = [
            #"ご利用金額[^0-9]*([0-9,]+)\s*円"#,
            #"利用金額[^0-9]*([0-9,]+)\s*円"#,
            #"金額[^0-9]*([0-9,]+)\s*円"#,
            #"([0-9,]+)\s*円"#
        ]
        for pattern in patterns {
            if let match = text.firstMatch(pattern: pattern), match.count > 1 {
                return Int(match[1].replacingOccurrences(of: ",", with: ""))
            }
        }
        return nil
    }

    private func extractDate(from text: String, now: Date) -> Date? {
        let normalized = text.replacingOccurrences(of: "年", with: "/")
            .replacingOccurrences(of: "月", with: "/")
            .replacingOccurrences(of: "日", with: "")

        let patterns = [
            #"(\d{4}/\d{1,2}/\d{1,2})"#,
            #"(\d{4}-\d{1,2}-\d{1,2})"#,
            #"(\d{1,2}/\d{1,2})"#
        ]

        for pattern in patterns {
            if let match = normalized.firstMatch(pattern: pattern), match.count > 1 {
                let raw = match[1]
                if raw.count == 5 || raw.count == 4 {
                    return parseMonthDay(raw, now: now)
                }
                return parseFullDate(raw)
            }
        }
        return nil
    }

    private func parseFullDate(_ raw: String) -> Date? {
        let formats = ["yyyy/MM/dd", "yyyy-MM-dd"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    private func parseMonthDay(_ raw: String, now: Date) -> Date? {
        let parts = raw.split(separator: "/")
        guard parts.count == 2,
              let month = Int(parts[0]),
              let day = Int(parts[1]) else { return nil }
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return cal.date(from: comps)
    }

    private func extractMerchant(from text: String) -> String? {
        let patterns = [
            #"ご利用先[:：]\s*(.+)"#,
            #"利用先[:：]\s*(.+)"#,
            #"加盟店[:：]\s*(.+)"#,
            #"店舗[:：]\s*(.+)"#
        ]
        for pattern in patterns {
            if let match = text.firstMatch(pattern: pattern), match.count > 1 {
                let candidate = match[1].split(separator: "\n").first.map(String.init)
                if let candidate, !candidate.isEmpty {
                    return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return nil
    }

    private func buildMemo(source: Source, merchant: String?) -> String {
        if let merchant, !merchant.isEmpty {
            return "\(source.rawValue)：\(merchant)"
        }
        return "\(source.rawValue) 利用"
    }

    private func categoryId(for source: Source, settings: EmailImportSettings, store: DataStore) -> UUID? {
        switch source {
        case .rakutenPay:
            return settings.rakutenPayCategoryId ?? store.categories.first?.id
        case .jcb:
            return settings.jcbCategoryId ?? store.categories.first?.id
        }
    }

    private func isDuplicate(_ receipt: ParsedReceipt, in transactions: [Transaction]) -> Bool {
        let cal = Calendar.current
        return transactions.contains(where: { tx in
            tx.amount == receipt.amount &&
            tx.memo == receipt.memo &&
            cal.isDate(tx.date, inSameDayAs: receipt.date)
        })
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private extension String {
    func firstMatch(pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range) else { return nil }
        return (0..<match.numberOfRanges).compactMap {
            guard let range = Range(match.range(at: $0), in: self) else { return nil }
            return String(self[range])
        }
    }
}
