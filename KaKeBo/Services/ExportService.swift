//
//  ExportService.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2026/05/18.
//

import Foundation
import UIKit

// MARK: - エクスポート設定

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv = "CSV"
    case pdf = "PDF"
    var id: String { rawValue }
}

enum ExportPeriod: Identifiable, Equatable {
    case currentMonth
    case previousMonth
    case custom(from: Date, to: Date)

    var id: String {
        switch self {
        case .currentMonth: return "current"
        case .previousMonth: return "previous"
        case .custom(let from, let to): return "custom-\(from)-\(to)"
        }
    }

    var label: String {
        switch self {
        case .currentMonth: return "今月"
        case .previousMonth: return "先月"
        case .custom: return "カスタム期間"
        }
    }
}

// MARK: - ExportService

struct ExportService {

    // MARK: - CSV 生成

    static func generateCSV(
        transactions: [Transaction],
        categories: [Category]
    ) -> Data {
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "ja_JP")

        var lines: [String] = []
        // BOM + ヘッダー
        lines.append("日付,種別,カテゴリ,金額,メモ,タグ")

        let sorted = transactions.sorted { $0.date < $1.date }
        for tx in sorted {
            let date = dateFormatter.string(from: tx.date)
            let type = tx.type.rawValue
            let category = categoryMap[tx.categoryId] ?? "不明"
            let amount = String(tx.amount)
            // メモ内のカンマ・改行・ダブルクォートをエスケープ
            let memo = escapeCSVField(tx.memo)
            let tags = escapeCSVField(tx.tags.joined(separator: "; "))
            lines.append("\(date),\(type),\(category),\(amount),\(memo),\(tags)")
        }

        let csv = lines.joined(separator: "\r\n")
        // BOM付きUTF-8（Excel対応）
        let bom = "\u{FEFF}"
        return (bom + csv).data(using: .utf8) ?? Data()
    }

    // MARK: - PDF 生成

    static func generatePDF(
        transactions: [Transaction],
        categories: [Category],
        title: String
    ) -> Data {
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let sorted = transactions.sorted { $0.date < $1.date }

        // 集計
        let totalIncome = sorted.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let totalExpense = sorted.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let balance = totalIncome - totalExpense

        // カテゴリ別支出
        var categoryTotals: [(name: String, amount: Int)] = []
        let expenseByCategory = Dictionary(grouping: sorted.filter { $0.type == .expense }, by: { $0.categoryId })
        for (catId, txs) in expenseByCategory {
            let name = categoryMap[catId] ?? "不明"
            let sum = txs.reduce(0) { $0 + $1.amount }
            categoryTotals.append((name, sum))
        }
        categoryTotals.sort { $0.amount > $1.amount }

        // PDF描画
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let margin: CGFloat = 40
        let contentWidth = pageRect.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            var y: CGFloat = 0

            func beginNewPage() {
                context.beginPage()
                y = margin
            }

            func checkPageBreak(needed: CGFloat) {
                if y + needed > pageRect.height - margin {
                    beginNewPage()
                }
            }

            // フォント定義
            let titleFont = UIFont.boldSystemFont(ofSize: 18)
            let headingFont = UIFont.boldSystemFont(ofSize: 14)
            let bodyFont = UIFont.systemFont(ofSize: 11)
            let smallFont = UIFont.systemFont(ofSize: 10)

            let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont]
            let headingAttr: [NSAttributedString.Key: Any] = [.font: headingFont]
            let bodyAttr: [NSAttributedString.Key: Any] = [.font: bodyFont]
            let smallAttr: [NSAttributedString.Key: Any] = [.font: smallFont, .foregroundColor: UIColor.darkGray]

            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            numberFormatter.locale = Locale(identifier: "ja_JP")

            func yen(_ amount: Int) -> String {
                "¥" + (numberFormatter.string(from: NSNumber(value: amount)) ?? "\(amount)")
            }

            // --- ページ1 開始 ---
            beginNewPage()

            // タイトル
            let titleStr = "KaKeBo 家計簿レポート" as NSString
            titleStr.draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttr)
            y += 28

            let subtitleStr = title as NSString
            subtitleStr.draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttr)
            y += 30

            // サマリー
            let summaryLines = [
                "収入合計:  \(yen(totalIncome))",
                "支出合計:  \(yen(totalExpense))",
                "収支:      \(yen(balance))"
            ]
            for line in summaryLines {
                (line as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttr)
                y += 18
            }
            y += 16

            // カテゴリ別支出
            if !categoryTotals.isEmpty {
                ("【カテゴリ別支出】" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: headingAttr)
                y += 22

                for cat in categoryTotals {
                    checkPageBreak(needed: 18)
                    let pct = totalExpense > 0 ? Double(cat.amount) / Double(totalExpense) * 100 : 0
                    let line = String(format: "  %-10s  %@  (%.1f%%)", (cat.name as NSString).utf8String ?? "", yen(cat.amount), pct)
                    // 日本語対応のため NSString で描画
                    let displayLine = "  \(cat.name)    \(yen(cat.amount))  (\(String(format: "%.1f", pct))%)"
                    (displayLine as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: bodyAttr)
                    y += 18
                }
                y += 16
            }

            // 取引明細
            checkPageBreak(needed: 40)
            ("【取引明細】" as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: headingAttr)
            y += 22

            // ヘッダー行
            let colDate: CGFloat = margin
            let colType: CGFloat = margin + 70
            let colCat: CGFloat = margin + 110
            let colAmount: CGFloat = margin + 200
            let colMemo: CGFloat = margin + 280

            ("日付" as NSString).draw(at: CGPoint(x: colDate, y: y), withAttributes: smallAttr)
            ("種別" as NSString).draw(at: CGPoint(x: colType, y: y), withAttributes: smallAttr)
            ("カテゴリ" as NSString).draw(at: CGPoint(x: colCat, y: y), withAttributes: smallAttr)
            ("金額" as NSString).draw(at: CGPoint(x: colAmount, y: y), withAttributes: smallAttr)
            ("メモ" as NSString).draw(at: CGPoint(x: colMemo, y: y), withAttributes: smallAttr)
            y += 16

            // 区切り線
            let linePath = UIBezierPath()
            linePath.move(to: CGPoint(x: margin, y: y))
            linePath.addLine(to: CGPoint(x: margin + contentWidth, y: y))
            UIColor.gray.setStroke()
            linePath.lineWidth = 0.5
            linePath.stroke()
            y += 6

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "M/d"
            dateFormatter.locale = Locale(identifier: "ja_JP")

            for tx in sorted {
                checkPageBreak(needed: 16)

                let date = dateFormatter.string(from: tx.date)
                let type = tx.type.rawValue
                let cat = categoryMap[tx.categoryId] ?? "不明"
                let amount = yen(tx.amount)
                // メモは長すぎる場合は切り詰め
                let memo = tx.memo.count > 20 ? String(tx.memo.prefix(20)) + "…" : tx.memo

                (date as NSString).draw(at: CGPoint(x: colDate, y: y), withAttributes: smallAttr)
                (type as NSString).draw(at: CGPoint(x: colType, y: y), withAttributes: smallAttr)
                (cat as NSString).draw(at: CGPoint(x: colCat, y: y), withAttributes: smallAttr)
                (amount as NSString).draw(at: CGPoint(x: colAmount, y: y), withAttributes: smallAttr)
                (memo as NSString).draw(at: CGPoint(x: colMemo, y: y), withAttributes: smallAttr)
                y += 16
            }

            // フッター
            y += 20
            checkPageBreak(needed: 20)
            let footer = "KaKeBo で作成 - \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))"
            (footer as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: smallAttr)
        }

        return data
    }

    // MARK: - ファイル書き出し

    static func writeToTemporaryFile(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url)
            return url
        } catch {
            print("ExportService: ファイル書き出しエラー - \(error)")
            return nil
        }
    }

    // MARK: - ヘルパー

    private static func escapeCSVField(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}
