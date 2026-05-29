import SwiftUI

/// ホーム画面に表示する予算アラートカード
/// 予算超過・警告（80%以上）のカテゴリを一覧表示
struct BudgetAlertCard: View {
    let alerts: [BudgetAlert]
    let onTapBudgetTab: () -> Void
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("予算アラート")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onTapBudgetTab()
                } label: {
                    Text("予算タブへ")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(themeStore.theme.accentColor(for: scheme))
                }
            }

            // アラート一覧
            ForEach(alerts) { alert in
                alertRow(alert)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func alertRow(_ alert: BudgetAlert) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: alert.symbolName)
                    .foregroundStyle(alert.categoryColor)
                    .frame(width: 20)

                Text(alert.categoryName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer()

                Text("\(currency(alert.expense)) / \(currency(alert.budget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(alert.isOver ? .red : .orange)
            }

            // プログレスバー
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.gray.opacity(0.12))
                        .frame(height: 5)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(alert.barColor.gradient)
                        .frame(width: geo.size.width * min(CGFloat(alert.ratio), 1.0), height: 5)
                }
            }
            .frame(height: 5)
        }
    }

    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "\u{00A5}" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
}

/// 予算アラート情報
struct BudgetAlert: Identifiable {
    let id: UUID
    let categoryName: String
    let symbolName: String
    let categoryColor: Color
    let expense: Int
    let budget: Int
    let ratio: Double

    var isOver: Bool { ratio >= 1.0 }

    var barColor: Color {
        if ratio >= 1.0 { return .red }
        return .orange
    }
}
