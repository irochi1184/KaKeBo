//
//  AnnualReportPDFService.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2026/05/19.
//

import UIKit

/// 年間レポートをカラフルなPDFとして生成するサービス
struct AnnualReportPDFService {

    // MARK: - 入力データ

    struct ReportData {
        let year: Int
        let yearIncome: Int
        let yearExpense: Int
        let yearBalance: Int
        let savingsRate: Double
        let avgExpensePerMonth: Int
        let monthlyIncome: [Int]   // index 0=1月 ... 11=12月
        let monthlyExpense: [Int]  // index 0=1月 ... 11=12月
        let categoryBreakdown: [CategoryEntry]
        let bestMonth: (month: Int, balance: Int)?
        let worstMonth: (month: Int, balance: Int)?

        // テーマカラー
        let accentColor: UIColor
        let incomeColor: UIColor
        let expenseColor: UIColor
    }

    struct CategoryEntry {
        let name: String
        let symbol: String
        let amount: Int
        let color: UIColor
    }

    // MARK: - PDF生成

    static func generate(data: ReportData) -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 595.2, height: 841.8) // A4
        let margin: CGFloat = 36
        let contentWidth = pageRect.width - margin * 2

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        return renderer.pdfData { ctx in
            var y: CGFloat = 0

            func newPage() {
                ctx.beginPage()
                y = margin
            }

            func needSpace(_ h: CGFloat) {
                if y + h > pageRect.height - margin { newPage() }
            }

            // --- ページ1: タイトル + KPI + 月別チャート ---
            newPage()

            // ヘッダー背景
            let headerRect = CGRect(x: 0, y: 0, width: pageRect.width, height: 80)
            data.accentColor.withAlphaComponent(0.12).setFill()
            UIBezierPath(rect: headerRect).fill()

            // タイトル
            let titleFont = UIFont.boldSystemFont(ofSize: 22)
            let titleAttr: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: UIColor.label]
            ("KaKeBo 年間レポート \(data.year)" as NSString).draw(at: CGPoint(x: margin, y: 24), withAttributes: titleAttr)

            let subtitleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.secondaryLabel
            ]
            let dateStr = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)
            ("作成日: \(dateStr)" as NSString).draw(at: CGPoint(x: margin, y: 54), withAttributes: subtitleAttr)

            y = 92

            // KPIカード
            y = drawKPISection(data: data, x: margin, y: y, width: contentWidth)
            y += 20

            // 月別収支バーチャート
            needSpace(200)
            y = drawSectionTitle("月別収支サマリー", x: margin, y: y, accent: data.accentColor)
            y = drawMonthlyBarChart(data: data, x: margin, y: y, width: contentWidth, height: 160)
            y += 20

            // --- カテゴリ別ドーナツ + 内訳表 ---
            needSpace(300)
            y = drawSectionTitle("カテゴリ別支出内訳", x: margin, y: y, accent: data.accentColor)
            y = drawCategorySection(data: data, x: margin, y: y, width: contentWidth)
            y += 20

            // --- ハイライト ---
            needSpace(80)
            y = drawHighlights(data: data, x: margin, y: y, width: contentWidth)
            y += 20

            // フッター
            needSpace(30)
            drawFooter(x: margin, y: pageRect.height - margin - 10, width: contentWidth)
        }
    }

    // MARK: - KPI セクション

    private static func drawKPISection(data: ReportData, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        var currentY = y
        let boxWidth = (width - 16) / 3
        let boxHeight: CGFloat = 52

        // 上段: 収入 / 支出 / 収支
        let topKPIs: [(String, Int, UIColor)] = [
            ("収入", data.yearIncome, data.incomeColor),
            ("支出", data.yearExpense, data.expenseColor),
            ("収支", data.yearBalance, data.yearBalance >= 0 ? UIColor.systemBlue : UIColor.systemOrange)
        ]

        for (i, kpi) in topKPIs.enumerated() {
            let bx = x + CGFloat(i) * (boxWidth + 8)
            drawKPIBox(title: kpi.0, value: formatYen(kpi.1), tint: kpi.2, rect: CGRect(x: bx, y: currentY, width: boxWidth, height: boxHeight))
        }
        currentY += boxHeight + 8

        // 下段: 貯蓄率 / 平均支出
        let bottomBoxWidth = (width - 8) / 2
        let bottomKPIs: [(String, String, UIColor)] = [
            ("貯蓄率", "\(Int(round(data.savingsRate * 100)))%", UIColor.systemPurple),
            ("平均支出/月", formatYen(data.avgExpensePerMonth), UIColor.systemPink)
        ]
        for (i, kpi) in bottomKPIs.enumerated() {
            let bx = x + CGFloat(i) * (bottomBoxWidth + 8)
            drawKPIBox(title: kpi.0, value: kpi.1, tint: kpi.2, rect: CGRect(x: bx, y: currentY, width: bottomBoxWidth, height: boxHeight))
        }
        currentY += boxHeight

        return currentY
    }

    private static func drawKPIBox(title: String, value: String, tint: UIColor, rect: CGRect) {
        // 背景
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        tint.withAlphaComponent(0.08).setFill()
        path.fill()
        tint.withAlphaComponent(0.2).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.label
        ]

        (title as NSString).draw(at: CGPoint(x: rect.midX - 20, y: rect.minY + 8), withAttributes: titleAttr)

        let valueSize = (value as NSString).size(withAttributes: valueAttr)
        (value as NSString).draw(at: CGPoint(x: rect.midX - valueSize.width / 2, y: rect.minY + 26), withAttributes: valueAttr)
    }

    // MARK: - 月別バーチャート

    private static func drawMonthlyBarChart(data: ReportData, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGFloat {
        let chartX = x + 40  // Y軸ラベル用の余白
        let chartWidth = width - 50
        let chartHeight = height - 30 // X軸ラベル用の余白
        let chartY = y

        // 最大値を取得
        let maxVal = max(
            data.monthlyIncome.max() ?? 1,
            data.monthlyExpense.max() ?? 1,
            1
        )

        let barGroupWidth = chartWidth / 12
        let barWidth = barGroupWidth * 0.3

        // Y軸グリッド線
        UIColor.separator.withAlphaComponent(0.3).setStroke()
        for i in 0...4 {
            let gy = chartY + chartHeight - (chartHeight * CGFloat(i) / 4)
            let gridPath = UIBezierPath()
            gridPath.move(to: CGPoint(x: chartX, y: gy))
            gridPath.addLine(to: CGPoint(x: chartX + chartWidth, y: gy))
            gridPath.lineWidth = 0.3
            gridPath.stroke()

            // Y軸ラベル
            let labelVal = maxVal * i / 4
            let label = shortYen(labelVal)
            let labelAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 7),
                .foregroundColor: UIColor.secondaryLabel
            ]
            (label as NSString).draw(at: CGPoint(x: x, y: gy - 5), withAttributes: labelAttr)
        }

        // バー描画
        for m in 0..<12 {
            let groupX = chartX + CGFloat(m) * barGroupWidth + barGroupWidth / 2

            // 収入バー
            let incHeight = maxVal > 0 ? CGFloat(data.monthlyIncome[m]) / CGFloat(maxVal) * chartHeight : 0
            let incRect = CGRect(
                x: groupX - barWidth - 1,
                y: chartY + chartHeight - incHeight,
                width: barWidth,
                height: max(incHeight, 0)
            )
            let incPath = UIBezierPath(roundedRect: incRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 2, height: 2))
            data.incomeColor.withAlphaComponent(0.8).setFill()
            incPath.fill()

            // 支出バー
            let expHeight = maxVal > 0 ? CGFloat(data.monthlyExpense[m]) / CGFloat(maxVal) * chartHeight : 0
            let expRect = CGRect(
                x: groupX + 1,
                y: chartY + chartHeight - expHeight,
                width: barWidth,
                height: max(expHeight, 0)
            )
            let expPath = UIBezierPath(roundedRect: expRect, byRoundingCorners: [.topLeft, .topRight], cornerRadii: CGSize(width: 2, height: 2))
            data.expenseColor.withAlphaComponent(0.8).setFill()
            expPath.fill()

            // X軸ラベル
            let labelAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.secondaryLabel
            ]
            ("\(m + 1)月" as NSString).draw(at: CGPoint(x: groupX - 8, y: chartY + chartHeight + 4), withAttributes: labelAttr)
        }

        // 凡例
        let legendY = chartY + chartHeight + 18
        drawLegendDot(color: data.incomeColor, label: "収入", x: chartX, y: legendY)
        drawLegendDot(color: data.expenseColor, label: "支出", x: chartX + 60, y: legendY)

        return y + height
    }

    // MARK: - カテゴリ別セクション

    private static func drawCategorySection(data: ReportData, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        guard !data.categoryBreakdown.isEmpty else { return y }

        var currentY = y
        let totalExpense = data.categoryBreakdown.reduce(0) { $0 + $1.amount }

        // ドーナツチャート
        let donutCenter = CGPoint(x: x + width / 2, y: currentY + 90)
        let outerRadius: CGFloat = 80
        let innerRadius: CGFloat = 48

        var startAngle: CGFloat = -.pi / 2

        for cat in data.categoryBreakdown {
            let share = CGFloat(cat.amount) / max(CGFloat(totalExpense), 1)
            let endAngle = startAngle + share * 2 * .pi

            let path = UIBezierPath()
            path.move(to: CGPoint(
                x: donutCenter.x + innerRadius * cos(startAngle),
                y: donutCenter.y + innerRadius * sin(startAngle)
            ))
            path.addArc(withCenter: donutCenter, radius: outerRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
            path.addArc(withCenter: donutCenter, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: false)
            path.close()

            cat.color.setFill()
            path.fill()

            startAngle = endAngle
        }

        // ドーナツ中央テキスト
        let centerTitleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let centerValueAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: UIColor.label
        ]
        let totalStr = formatYen(totalExpense)
        let totalSize = (totalStr as NSString).size(withAttributes: centerValueAttr)
        ("合計" as NSString).draw(at: CGPoint(x: donutCenter.x - 10, y: donutCenter.y - 14), withAttributes: centerTitleAttr)
        (totalStr as NSString).draw(at: CGPoint(x: donutCenter.x - totalSize.width / 2, y: donutCenter.y + 2), withAttributes: centerValueAttr)

        currentY += 185

        // カテゴリ別テーブル
        let nameAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.label
        ]
        let amountAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 10),
            .foregroundColor: UIColor.label
        ]
        let pctAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.secondaryLabel
        ]

        // ヘッダー
        let headerAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 9),
            .foregroundColor: UIColor.secondaryLabel
        ]
        ("カテゴリ" as NSString).draw(at: CGPoint(x: x + 20, y: currentY), withAttributes: headerAttr)
        ("金額" as NSString).draw(at: CGPoint(x: x + width - 140, y: currentY), withAttributes: headerAttr)
        ("割合" as NSString).draw(at: CGPoint(x: x + width - 60, y: currentY), withAttributes: headerAttr)
        currentY += 16

        // 区切り線
        drawDivider(x: x, y: currentY, width: width, color: data.accentColor.withAlphaComponent(0.3))
        currentY += 4

        for cat in data.categoryBreakdown {
            // カラードット
            let dotRect = CGRect(x: x + 4, y: currentY + 3, width: 8, height: 8)
            cat.color.setFill()
            UIBezierPath(ovalIn: dotRect).fill()

            // カテゴリ名
            (cat.name as NSString).draw(at: CGPoint(x: x + 20, y: currentY), withAttributes: nameAttr)

            // 金額
            let amountStr = formatYen(cat.amount)
            (amountStr as NSString).draw(at: CGPoint(x: x + width - 140, y: currentY), withAttributes: amountAttr)

            // 割合 + バー
            let pct = totalExpense > 0 ? Double(cat.amount) / Double(totalExpense) * 100 : 0
            let pctStr = String(format: "%.1f%%", pct)
            (pctStr as NSString).draw(at: CGPoint(x: x + width - 60, y: currentY), withAttributes: pctAttr)

            // ミニプログレスバー
            let barX = x + width - 30
            let barWidth: CGFloat = 30
            let barRect = CGRect(x: barX, y: currentY + 3, width: barWidth, height: 6)
            UIColor.systemGray5.setFill()
            UIBezierPath(roundedRect: barRect, cornerRadius: 3).fill()
            let filledWidth = barWidth * CGFloat(pct) / 100
            let filledRect = CGRect(x: barX, y: currentY + 3, width: filledWidth, height: 6)
            cat.color.setFill()
            UIBezierPath(roundedRect: filledRect, cornerRadius: 3).fill()

            currentY += 18
        }

        return currentY
    }

    // MARK: - ハイライト

    private static func drawHighlights(data: ReportData, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        var currentY = drawSectionTitle("ハイライト", x: x, y: y, accent: data.accentColor)

        let boxWidth = (width - 12) / 2
        let boxHeight: CGFloat = 50

        // ベスト月
        if let best = data.bestMonth {
            let rect = CGRect(x: x, y: currentY, width: boxWidth, height: boxHeight)
            drawHighlightBox(title: "ベスト月", subtitle: "\(best.month)月", value: formatYen(best.balance), tint: data.incomeColor, rect: rect)
        }

        // ワースト月
        if let worst = data.worstMonth {
            let rect = CGRect(x: x + boxWidth + 12, y: currentY, width: boxWidth, height: boxHeight)
            drawHighlightBox(title: "ワースト月", subtitle: "\(worst.month)月", value: formatYen(worst.balance), tint: data.expenseColor, rect: rect)
        }

        return currentY + boxHeight
    }

    private static func drawHighlightBox(title: String, subtitle: String, value: String, tint: UIColor, rect: CGRect) {
        let path = UIBezierPath(roundedRect: rect, cornerRadius: 10)
        tint.withAlphaComponent(0.06).setFill()
        path.fill()
        tint.withAlphaComponent(0.2).setStroke()
        path.lineWidth = 0.8
        path.stroke()

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let subtitleAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.label
        ]
        let valueAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 12),
            .foregroundColor: UIColor.label
        ]

        (title as NSString).draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 8), withAttributes: titleAttr)
        (subtitle as NSString).draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 24), withAttributes: subtitleAttr)
        let valSize = (value as NSString).size(withAttributes: valueAttr)
        (value as NSString).draw(at: CGPoint(x: rect.maxX - valSize.width - 10, y: rect.minY + 24), withAttributes: valueAttr)
    }

    // MARK: - ヘルパー

    private static func drawSectionTitle(_ title: String, x: CGFloat, y: CGFloat, accent: UIColor) -> CGFloat {
        // アクセントカラーの左バー
        let barRect = CGRect(x: x, y: y + 2, width: 3, height: 14)
        accent.setFill()
        UIBezierPath(roundedRect: barRect, cornerRadius: 1.5).fill()

        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 14),
            .foregroundColor: UIColor.label
        ]
        (title as NSString).draw(at: CGPoint(x: x + 10, y: y), withAttributes: attr)
        return y + 24
    }

    private static func drawDivider(x: CGFloat, y: CGFloat, width: CGFloat, color: UIColor) {
        color.setStroke()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: x, y: y))
        path.addLine(to: CGPoint(x: x + width, y: y))
        path.lineWidth = 0.5
        path.stroke()
    }

    private static func drawLegendDot(color: UIColor, label: String, x: CGFloat, y: CGFloat) {
        let dotRect = CGRect(x: x, y: y + 2, width: 8, height: 8)
        color.setFill()
        UIBezierPath(roundedRect: dotRect, cornerRadius: 2).fill()

        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.secondaryLabel
        ]
        (label as NSString).draw(at: CGPoint(x: x + 12, y: y), withAttributes: attr)
    }

    private static func drawFooter(x: CGFloat, y: CGFloat, width: CGFloat) {
        let attr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let text = "KaKeBo で作成 - \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none))"
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attr)
    }

    private static func formatYen(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: NSNumber(value: amount)) ?? "\(amount)")
    }

    private static func shortYen(_ amount: Int) -> String {
        if amount >= 10_000_000 { return String(format: "%.0f百万", Double(amount) / 1_000_000) }
        if amount >= 10_000 { return String(format: "%.0f万", Double(amount) / 10_000) }
        if amount >= 1_000 { return String(format: "%.1fk", Double(amount) / 1_000) }
        return "¥\(amount)"
    }
}
