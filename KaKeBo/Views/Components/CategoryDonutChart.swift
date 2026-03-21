//
//  Views/Components/CategoryDonutChart.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import Charts

struct CategorySlice: Identifiable, Hashable {
    let id: UUID
    let name: String
    let color: Color
    let value: Int
    let filterKey: String
    let symbolName: String?

    init(id: UUID, name: String, color: Color, value: Int, filterKey: String? = nil, symbolName: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.value = value
        self.filterKey = filterKey ?? id.uuidString
        self.symbolName = symbolName
    }
}

struct CategoryDonutChart: View {
    let breakdown: [CategorySlice]
    let currentTotal: Int
    let previousTotal: Int
    var minShareToShowLabel: Double = 0.08
    var isExpense: Bool = true // 表示バッジの文言/色に反映
    var useFlatStyle: Bool = false
    
    @Environment(\.appIncomeColor) private var incomeColor
    @Environment(\.appExpenseColor) private var expenseColor
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {

            VStack(alignment: .leading, spacing: 12) {
                // 見出し行
                HStack(alignment: .firstTextBaseline) {
                    HStack(spacing: 8) {
                        // タイプチップ（支出/収入）
                        Label(isExpense ? "支出" : "収入",
                              systemImage: isExpense ? "arrow.down.circle" : "arrow.up.circle")
                        .font(.caption.weight(.semibold))
                        .padding(.vertical, 4).padding(.horizontal, 8)
                        .background(
                            Capsule().fill((isExpense ? expenseColor : incomeColor).opacity(0.15))
                        )
                        .foregroundStyle(isExpense ? expenseColor : incomeColor)
                    }
                    
                    Spacer()
                    
                    DiffBadge(
                        current: currentTotal,
                        previous: previousTotal,
                        mode: isExpense ? .expense : .balance,
                        useFlatStyle: useFlatStyle,
                        incomeColor: incomeColor,
                        expenseColor: expenseColor
                    )
                }
                
                // ドーナツ
                Chart(breakdown) { item in
                    SectorMark(
                        angle: .value("金額", item.value),
                        innerRadius: .ratio(0.62),
                        outerRadius: .ratio(1.0)
                    )
                    .foregroundStyle(item.color)
                    .annotation(position: .overlay, alignment: .center) {
                        if share(of: item) >= minShareToShowLabel {
                            // 読みやすいラベル（ぼかし＋白字）
                            VStack(spacing: 2) {
                                Text(item.name)
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                Text(currency(item.value))
                                    .font(.caption2)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 3).padding(.horizontal, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.15)))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                            .allowsHitTesting(false)
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 220)
                .chartLegend(.hidden)
                .chartPlotStyle { plot in
                    // プロット面も透けるように
                    plot.background(.clear)
                }
                .padding(.bottom, 15)
                
                // レジェンド（上位）
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(breakdown) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.color).frame(width: 10, height: 10)
                            Text(item.name).font(.caption)
                            Spacer()
                            Text(currency(item.value))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
//            .homeCard()
    }
    
    // MARK: - Helpers
    private var total: Int { breakdown.reduce(0) { $0 + $1.value } }
    private func share(of item: CategorySlice) -> Double {
        guard total > 0 else { return 0 }
        return Double(item.value) / Double(total)
    }
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}

// 先月比の小さなバッジ
private struct DiffBadge: View {
    enum Mode { case expense, balance }  // ← 追加
    let current: Int
    let previous: Int
    var mode: Mode = .expense            // ← 既定は “支出”
    var useFlatStyle: Bool = false
    var incomeColor: Color = .green
    var expenseColor: Color = .red
    
    var body: some View {
        let percent: Double? = {
            switch mode {
            case .expense:
                let prev = max(0, previous)
                let curr = max(0, current)
                guard prev > 0 else { return nil }
                return (Double(curr - prev) / Double(prev)) * 100.0
            case .balance:
                let denom = abs(Double(previous))
                guard denom > 0 else { return nil }
                return (Double(current - previous) / denom) * 100.0
            }
        }()
        
        // 表示テキスト & 色
        let (text, bg, icon): (String, Color, String) = {
            if let p = percent {
                let v = round(p) // 小数不要なら丸め
                if v > 0 {
                    // 支出: 赤（悪化） / 収支: 緑（改善）
                    let color: Color = (mode == .expense) ? expenseColor.opacity(0.85) : incomeColor.opacity(0.85)
                    return ("先月比 +\(Int(v))%", color, "arrow.up.right")
                } else if v < 0 {
                    let color: Color = (mode == .expense) ? incomeColor.opacity(0.85) : expenseColor.opacity(0.85)
                    return ("先月比 \(Int(v))%", color, "arrow.down.right")
                } else {
                    return ("先月比 ±0%", .secondary, "arrow.right")
                }
            } else {
                // 前月0円などで %が出せない時
                return ("先月比", .secondary, "minus")
            }
        }()
        let fillStyle: AnyShapeStyle = useFlatStyle
            ? AnyShapeStyle(bg.opacity(0.12))
            : AnyShapeStyle(bg.gradient.opacity(0.85))
        
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(useFlatStyle ? bg : .white)
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(fillStyle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(useFlatStyle ? bg.opacity(0.25) : .white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct CategoryDonutPager: View {
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme
    // 支出
    let expense: [CategorySlice]
    let expenseCurrentTotal: Int
    let expensePreviousTotal: Int
    // 収入
    let income: [CategorySlice]
    let incomeCurrentTotal: Int
    let incomePreviousTotal: Int
    
    @State private var page = 0
    
    var body: some View {
        let accent = themeStore.theme.accentColor(for: scheme)
        let isFlat = themeStore.theme.homeCardStyle == .flat
        let pagerHeight = max(requiredHeight(forCount: expense.count),
                              requiredHeight(forCount: income.count))
        
        VStack(alignment: .leading, spacing: 6) {
            Text("カテゴリ別グラフ")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            
            ZStack {
                TabView(selection: $page) {
                    // 支出
                    VStack(spacing: 0) {
                        CategoryDonutChart(
                            breakdown: expense,
                            currentTotal: expenseCurrentTotal,
                            previousTotal: expensePreviousTotal,
                            isExpense: true,
                            useFlatStyle: isFlat
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .tag(0)
                    
                    // 収入
                    VStack(spacing: 0) {
                        CategoryDonutChart(
                            breakdown: income,
                            currentTotal: incomeCurrentTotal,
                            previousTotal: incomePreviousTotal,
                            isExpense: false,
                            useFlatStyle: isFlat
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .tag(1)
                }
                // ドット非表示
                .tabViewStyle(.page(indexDisplayMode: .never))
                
                // ▼ 左右の矢印オーバーレイ
                HStack {
                    // 左
                    Button {
                        withAnimation(.interactiveSpring()) { page = max(page - 1, 0) }
                    } label: {
                        Image(systemName: isFlat ? "chevron.left" : "chevron.left.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(accent)
                            .opacity(page == 0 ? 0.25 : 0.9)
                            .padding(4)
                            .background(
                                Group {
                                    if !isFlat {
                                        Circle().fill(.ultraThinMaterial)
                                    }
                                }
                            )
                    }
                    .disabled(page == 0)
                    .accessibilityLabel("前のページ")
                    
                    Spacer(minLength: 0)
                    
                    // 右
                    Button {
                        withAnimation(.interactiveSpring()) { page = min(page + 1, 1) }
                    } label: {
                        Image(systemName: isFlat ? "chevron.right" : "chevron.right.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(accent)
                            .opacity(page == 1 ? 0.25 : 0.9)
                            .padding(4)
                            .background(
                                Group {
                                    if !isFlat {
                                        Circle().fill(.ultraThinMaterial)
                                    }
                                }
                            )
                    }
                    .disabled(page == 1)
                    .accessibilityLabel("次のページ")
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 55) // ★ ここで上からの距離を固定
                .allowsHitTesting(true) // ← これで矢印がタップ可能に
                .zIndex(10)
            }
            .frame(height: pagerHeight)   // ← 動的高さ
            .homeCard()
        }
    }
    
    // MARK: - 高さ見積り
    private func requiredHeight(forCount count: Int) -> CGFloat {
        // 構成: ヘッダ(タイトル+先月比) + ドーナツ + レジェンド行数
        let header: CGFloat = 44            // タイトル行の目安
        let chart: CGFloat  = 220           // ドーナツ高さ
        let legend = legendHeight(forCount: count)
        let paddings: CGFloat = 12 + 4     // VStackの上下マージン目安
        let total = header + chart + legend + paddings
        
        // 下限/上限（上限超えたら中スクロールさせる想定）
        return min(max(total, 320), 520)
    }
    
    private func legendHeight(forCount count: Int) -> CGFloat {
        // 2列グリッド。行数 = ceil(count/2)
        let rows = Int(ceil(Double(count) / 2.0))
        let rowHeight: CGFloat = 20         // caption行の目安
        let rowSpacing: CGFloat = 8
        return CGFloat(rows) * rowHeight + CGFloat(max(0, rows-1)) * rowSpacing
    }
}
