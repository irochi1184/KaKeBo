//
//  ExportService.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2026/05/18.
//

import Foundation
import UIKit
import SwiftUI

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

    // MARK: - テーマカラー

    struct ThemeColors {
        let accent: UIColor
        let income: UIColor
        let expense: UIColor
    }

    // MARK: - PDF 生成（リッチデザイン版）

    static func generatePDF(
        transactions: [Transaction],
        categories: [Category],
        title: String,
        theme: ThemeColors? = nil
    ) -> Data {
        let accentColor = theme?.accent ?? UIColor.systemBlue
        let incomeColor = theme?.income ?? UIColor.systemGreen
        let expenseColor = theme?.expense ?? UIColor.systemRed

        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        let sorted = transactions.sorted { $0.date < $1.date }

        // 集計
        let totalIncome = sorted.filter { $0.type == .income }.reduce(0) { $0 + $1.amount }
        let totalExpense = sorted.filter { $0.type == .expense }.reduce(0) { $0 + $1.amount }
        let balance = totalIncome - totalExpense

        // カテゴリ別支出（色情報付き）
        var catTotals: [(name: String, amount: Int, color: UIColor)] = []
        let expenseByCategory = Dictionary(grouping: sorted.filter { $0.type == .expense }, by: { $0.categoryId })
        for (catId, txs) in expenseByCategory {
            let cat = categoryMap[catId]
            let name = cat?.name ?? "不明"
            let sum = txs.reduce(0) { $0 + $1.amount }
            let color = cat.flatMap { UIColor(Color.fromHex($0.colorHex) ?? .gray) } ?? .gray
            catTotals.append((name, sum, color))
        }
        catTotals.sort { $0.amount > $1.amount }

        // 日別支出集計
        let cal = Calendar.current
        var dailyExpenses: [Date: Int] = [:]
        for tx in sorted where tx.type == .expense {
            let day = cal.startOfDay(for: tx.date)
            dailyExpenses[day, default: 0] += tx.amount
        }

        // PDF描画
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let margin: CGFloat = 36
        let contentWidth = pageRect.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            var y: CGFloat = 0

            func newPage() { context.beginPage(); y = margin }
            func needSpace(_ h: CGFloat) { if y + h > pageRect.height - margin { newPage() } }

            let nf = NumberFormatter()
            nf.numberStyle = .decimal
            nf.groupingSeparator = ","
            func yen(_ n: Int) -> String { "¥" + (nf.string(from: NSNumber(value: n)) ?? "\(n)") }

            // --- ページ1 ---
            newPage()

            // ヘッダー帯
            accentColor.withAlphaComponent(0.12).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: pageRect.width, height: 76)).fill()

            let titleAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.label]
            ("KaKeBo 家計簿レポート" as NSString).draw(at: CGPoint(x: margin, y: 20), withAttributes: titleAttr)

            let subAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.secondaryLabel]
            (title as NSString).draw(at: CGPoint(x: margin, y: 48), withAttributes: subAttr)

            y = 88

            // KPIカード（収入・支出・収支）
            let kpiWidth = (contentWidth - 16) / 3
            let kpiHeight: CGFloat = 50
            let kpis: [(String, Int, UIColor)] = [
                ("収入", totalIncome, incomeColor),
                ("支出", totalExpense, expenseColor),
                ("収支", balance, balance >= 0 ? UIColor.systemBlue : UIColor.systemOrange)
            ]
            for (i, kpi) in kpis.enumerated() {
                let bx = margin + CGFloat(i) * (kpiWidth + 8)
                let rect = CGRect(x: bx, y: y, width: kpiWidth, height: kpiHeight)
                drawKPIBox(title: kpi.0, value: yen(kpi.1), tint: kpi.2, rect: rect)
            }
            y += kpiHeight + 16

            // カテゴリ別ドーナツチャート + テーブル
            if !catTotals.isEmpty {
                needSpace(280)
                y = drawSectionBar("カテゴリ別支出内訳", x: margin, y: y, accent: accentColor)

                // ドーナツ
                let donutCenter = CGPoint(x: margin + contentWidth / 2, y: y + 80)
                let outerR: CGFloat = 70
                let innerR: CGFloat = 42
                var startAngle: CGFloat = -.pi / 2
                for cat in catTotals {
                    let share = CGFloat(cat.amount) / max(CGFloat(totalExpense), 1)
                    let endAngle = startAngle + share * 2 * .pi
                    let path = UIBezierPath()
                    path.move(to: CGPoint(x: donutCenter.x + innerR * cos(startAngle), y: donutCenter.y + innerR * sin(startAngle)))
                    path.addArc(withCenter: donutCenter, radius: outerR, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                    path.addArc(withCenter: donutCenter, radius: innerR, startAngle: endAngle, endAngle: startAngle, clockwise: false)
                    path.close()
                    cat.color.setFill()
                    path.fill()
                    startAngle = endAngle
                }
                // 中央テキスト
                let cAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.secondaryLabel]
                let cvAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 12), .foregroundColor: UIColor.label]
                ("合計" as NSString).draw(at: CGPoint(x: donutCenter.x - 10, y: donutCenter.y - 12), withAttributes: cAttr)
                let totalStr = yen(totalExpense)
                let totalSize = (totalStr as NSString).size(withAttributes: cvAttr)
                (totalStr as NSString).draw(at: CGPoint(x: donutCenter.x - totalSize.width / 2, y: donutCenter.y + 2), withAttributes: cvAttr)

                y += 170

                // カテゴリテーブル
                let hdrAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 9), .foregroundColor: UIColor.secondaryLabel]
                ("カテゴリ" as NSString).draw(at: CGPoint(x: margin + 18, y: y), withAttributes: hdrAttr)
                ("金額" as NSString).draw(at: CGPoint(x: margin + contentWidth - 140, y: y), withAttributes: hdrAttr)
                ("割合" as NSString).draw(at: CGPoint(x: margin + contentWidth - 60, y: y), withAttributes: hdrAttr)
                y += 14
                accentColor.withAlphaComponent(0.3).setStroke()
                let divPath = UIBezierPath()
                divPath.move(to: CGPoint(x: margin, y: y))
                divPath.addLine(to: CGPoint(x: margin + contentWidth, y: y))
                divPath.lineWidth = 0.5
                divPath.stroke()
                y += 4

                let nameAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10), .foregroundColor: UIColor.label]
                let amtAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 10), .foregroundColor: UIColor.label]
                let pctAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.secondaryLabel]

                for cat in catTotals {
                    needSpace(18)
                    // カラードット
                    cat.color.setFill()
                    UIBezierPath(ovalIn: CGRect(x: margin + 4, y: y + 3, width: 8, height: 8)).fill()
                    (cat.name as NSString).draw(at: CGPoint(x: margin + 18, y: y), withAttributes: nameAttr)
                    (yen(cat.amount) as NSString).draw(at: CGPoint(x: margin + contentWidth - 140, y: y), withAttributes: amtAttr)

                    let pct = totalExpense > 0 ? Double(cat.amount) / Double(totalExpense) * 100 : 0
                    (String(format: "%.1f%%", pct) as NSString).draw(at: CGPoint(x: margin + contentWidth - 60, y: y), withAttributes: pctAttr)

                    // ミニプログレスバー
                    let barX = margin + contentWidth - 30
                    let barW: CGFloat = 30
                    UIColor.systemGray5.setFill()
                    UIBezierPath(roundedRect: CGRect(x: barX, y: y + 3, width: barW, height: 6), cornerRadius: 3).fill()
                    cat.color.setFill()
                    UIBezierPath(roundedRect: CGRect(x: barX, y: y + 3, width: barW * CGFloat(pct) / 100, height: 6), cornerRadius: 3).fill()

                    y += 18
                }
                y += 16
            }

            // 日別支出バーチャート
            if !dailyExpenses.isEmpty {
                needSpace(180)
                y = drawSectionBar("日別支出推移", x: margin, y: y, accent: accentColor)

                let sortedDays = dailyExpenses.sorted { $0.key < $1.key }
                let maxDaily = sortedDays.map(\.value).max() ?? 1
                let chartH: CGFloat = 100
                let chartW = contentWidth - 40
                let chartX = margin + 36
                let barCount = sortedDays.count
                let barW = max(min(chartW / CGFloat(barCount) - 1, 12), 2)

                // Y軸グリッド
                UIColor.separator.withAlphaComponent(0.3).setStroke()
                for i in 0...3 {
                    let gy = y + chartH - (chartH * CGFloat(i) / 3)
                    let gp = UIBezierPath()
                    gp.move(to: CGPoint(x: chartX, y: gy))
                    gp.addLine(to: CGPoint(x: chartX + chartW, y: gy))
                    gp.lineWidth = 0.3
                    gp.stroke()

                    let lbl = shortYen(maxDaily * i / 3)
                    let la: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 7), .foregroundColor: UIColor.secondaryLabel]
                    (lbl as NSString).draw(at: CGPoint(x: margin, y: gy - 5), withAttributes: la)
                }

                // バー描画
                let df = DateFormatter()
                df.dateFormat = "M/d"
                df.locale = Locale(identifier: "ja_JP")
                let xLabelAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 6), .foregroundColor: UIColor.secondaryLabel]

                for (i, entry) in sortedDays.enumerated() {
                    let bh = maxDaily > 0 ? CGFloat(entry.value) / CGFloat(maxDaily) * chartH : 0
                    let bx = chartX + CGFloat(i) * (chartW / CGFloat(barCount))
                    let rect = CGRect(x: bx, y: y + chartH - bh, width: barW, height: max(bh, 1))
                    expenseColor.withAlphaComponent(0.7).setFill()
                    UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 1.5, height: 1.5)).fill()

                    // X軸ラベル（間引き表示）
                    if barCount <= 15 || i % max(barCount / 10, 1) == 0 {
                        let lbl = df.string(from: entry.key)
                        (lbl as NSString).draw(at: CGPoint(x: bx - 4, y: y + chartH + 3), withAttributes: xLabelAttr)
                    }
                }

                y += chartH + 20
            }

            // 取引明細
            needSpace(40)
            y = drawSectionBar("取引明細", x: margin, y: y, accent: accentColor)

            // ヘッダー行
            let colDate = margin
            let colType = margin + 50
            let colCat = margin + 90
            let colAmount = margin + 190
            let colMemo = margin + 270
            let tblHdrAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 8), .foregroundColor: UIColor.secondaryLabel]
            ("日付" as NSString).draw(at: CGPoint(x: colDate, y: y), withAttributes: tblHdrAttr)
            ("種別" as NSString).draw(at: CGPoint(x: colType, y: y), withAttributes: tblHdrAttr)
            ("カテゴリ" as NSString).draw(at: CGPoint(x: colCat, y: y), withAttributes: tblHdrAttr)
            ("金額" as NSString).draw(at: CGPoint(x: colAmount, y: y), withAttributes: tblHdrAttr)
            ("メモ" as NSString).draw(at: CGPoint(x: colMemo, y: y), withAttributes: tblHdrAttr)
            y += 14
            accentColor.withAlphaComponent(0.3).setStroke()
            let tblDiv = UIBezierPath()
            tblDiv.move(to: CGPoint(x: margin, y: y))
            tblDiv.addLine(to: CGPoint(x: margin + contentWidth, y: y))
            tblDiv.lineWidth = 0.5
            tblDiv.stroke()
            y += 4

            let df2 = DateFormatter()
            df2.dateFormat = "M/d"
            df2.locale = Locale(identifier: "ja_JP")
            let rowAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.darkGray]

            for (i, tx) in sorted.enumerated() {
                needSpace(15)

                // 交互背景
                if i % 2 == 0 {
                    UIColor.systemGray6.setFill()
                    UIBezierPath(rect: CGRect(x: margin, y: y - 1, width: contentWidth, height: 14)).fill()
                }

                let catName = categoryMap[tx.categoryId]?.name ?? "不明"
                let catColor = categoryMap[tx.categoryId].flatMap { UIColor(Color.fromHex($0.colorHex) ?? .gray) } ?? .gray

                (df2.string(from: tx.date) as NSString).draw(at: CGPoint(x: colDate, y: y), withAttributes: rowAttr)

                // 種別カラー
                let typeColor = tx.type == .income ? incomeColor : expenseColor
                let typeAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: typeColor]
                (tx.type.rawValue as NSString).draw(at: CGPoint(x: colType, y: y), withAttributes: typeAttr)

                // カテゴリドット + 名前
                catColor.setFill()
                UIBezierPath(ovalIn: CGRect(x: colCat, y: y + 2, width: 6, height: 6)).fill()
                (catName as NSString).draw(at: CGPoint(x: colCat + 10, y: y), withAttributes: rowAttr)

                (yen(tx.amount) as NSString).draw(at: CGPoint(x: colAmount, y: y), withAttributes: rowAttr)

                let memo = tx.memo.count > 22 ? String(tx.memo.prefix(22)) + "…" : tx.memo
                (memo as NSString).draw(at: CGPoint(x: colMemo, y: y), withAttributes: rowAttr)

                y += 15
            }

            // フッター
            y += 16
            needSpace(16)
            let footerAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 8), .foregroundColor: UIColor.tertiaryLabel]
            let footer = "KaKeBo で作成 - \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))"
            (footer as NSString).draw(at: CGPoint(x: margin, y: y), withAttributes: footerAttr)
        }

        return data
    }

    // MARK: - PDF描画ヘルパー

    private static func drawKPIBox(title: String, value: String, tint: UIColor, rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        tint.withAlphaComponent(0.08).setFill()
        path.fill()
        tint.withAlphaComponent(0.2).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let tAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 9), .foregroundColor: UIColor.secondaryLabel]
        let vAttr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.label]

        let tSize = (title as NSString).size(withAttributes: tAttr)
        (title as NSString).draw(at: CGPoint(x: rect.midX - tSize.width / 2, y: rect.minY + 6), withAttributes: tAttr)
        let vSize = (value as NSString).size(withAttributes: vAttr)
        (value as NSString).draw(at: CGPoint(x: rect.midX - vSize.width / 2, y: rect.minY + 24), withAttributes: vAttr)
    }

    private static func drawSectionBar(_ title: String, x: CGFloat, y: CGFloat, accent: UIColor) -> CGFloat {
        accent.setFill()
        UIBezierPath(roundedRect: CGRect(x: x, y: y + 2, width: 3, height: 14), cornerRadius: 1.5).fill()
        let attr: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.label]
        (title as NSString).draw(at: CGPoint(x: x + 10, y: y), withAttributes: attr)
        return y + 22
    }

    private static func shortYen(_ amount: Int) -> String {
        if amount >= 10_000_000 { return String(format: "%.0f百万", Double(amount) / 1_000_000) }
        if amount >= 10_000 { return String(format: "%.0f万", Double(amount) / 10_000) }
        if amount >= 1_000 { return String(format: "%.1fk", Double(amount) / 1_000) }
        return "¥\(amount)"
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
