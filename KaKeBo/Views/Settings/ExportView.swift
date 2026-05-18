//
//  ExportView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2026/05/18.
//

import SwiftUI

struct ExportView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var monthStartStore: MonthStartStore
    @EnvironmentObject var pm: PurchaseManager

    @State private var format: ExportFormat = .csv
    @State private var periodSelection: Int = 0 // 0=今月, 1=先月, 2=カスタム
    @State private var customFrom: Date = Date()
    @State private var customTo: Date = Date()
    @State private var filterType: Int = 0 // 0=すべて, 1=支出, 2=収入
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showPaywall = false

    // 無料プランの月間エクスポート回数制限
    @AppStorage("export.count.month", store: .appGroup) private var exportCountRaw: String = ""

    private var exportCount: Int {
        let key = currentMonthKey()
        let parts = exportCountRaw.split(separator: ":")
        if parts.count == 2, String(parts[0]) == key {
            return Int(parts[1]) ?? 0
        }
        return 0
    }

    private let freeLimit = 3

    var body: some View {
        Form {
            // フォーマット選択
            Section("出力形式") {
                Picker("形式", selection: $format) {
                    ForEach(ExportFormat.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)

                if format == .csv {
                    Text("Excel や Google スプレッドシートで開けます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("カテゴリ別集計と明細を含むレポートを作成します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 期間選択
            Section("期間") {
                Picker("期間", selection: $periodSelection) {
                    Text("今月").tag(0)
                    Text("先月").tag(1)
                    Text("カスタム").tag(2)
                }
                .pickerStyle(.segmented)

                if periodSelection == 2 {
                    DatePicker("開始日", selection: $customFrom, displayedComponents: .date)
                    DatePicker("終了日", selection: $customTo, displayedComponents: .date)
                }

                if !pm.isPremiumActive && periodSelection == 2 {
                    premiumBadge("カスタム期間はプレミアム機能です")
                }
            }

            // フィルター
            Section("フィルター") {
                Picker("種別", selection: $filterType) {
                    Text("すべて").tag(0)
                    Text("支出のみ").tag(1)
                    Text("収入のみ").tag(2)
                }
            }

            // プレビュー情報
            Section {
                let txCount = filteredTransactions().count
                HStack {
                    Text("対象取引数")
                    Spacer()
                    Text("\(txCount) 件")
                        .foregroundStyle(.secondary)
                }
            }

            // エクスポートボタン
            Section {
                Button {
                    performExport()
                } label: {
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .padding(.trailing, 8)
                        }
                        Label("エクスポート", systemImage: "square.and.arrow.up")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                .disabled(isExporting || filteredTransactions().isEmpty)

                if !pm.isPremiumActive {
                    Text("無料プラン: 今月あと \(max(0, freeLimit - exportCount)) 回（月\(freeLimit)回まで）")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("データ書き出し")
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(accent: .accentColor)
        }
        .alert("エクスポートエラー", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "不明なエラーが発生しました。")
        }
    }

    // MARK: - エクスポート実行

    private func performExport() {
        // 無料プラン制限チェック
        if !pm.isPremiumActive {
            if periodSelection == 2 {
                showPaywall = true
                return
            }
            if exportCount >= freeLimit {
                showPaywall = true
                return
            }
        }

        isExporting = true

        let transactions = filteredTransactions()
        let categories = store.categories

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        dateFormatter.locale = Locale(identifier: "ja_JP")

        let periodLabel = periodTitle()
        let timestamp = dateFormatter.string(from: Date())

        var fileURL: URL?

        switch format {
        case .csv:
            let data = ExportService.generateCSV(transactions: transactions, categories: categories)
            let filename = "KaKeBo_\(timestamp).csv"
            fileURL = ExportService.writeToTemporaryFile(data: data, filename: filename)

        case .pdf:
            let data = ExportService.generatePDF(transactions: transactions, categories: categories, title: periodLabel)
            let filename = "KaKeBo_\(timestamp).pdf"
            fileURL = ExportService.writeToTemporaryFile(data: data, filename: filename)
        }

        isExporting = false

        if let url = fileURL {
            exportedURL = url
            incrementExportCount()
            showShareSheet = true
        } else {
            errorMessage = "ファイルの作成に失敗しました。"
            showError = true
        }
    }

    // MARK: - フィルタリング

    private func filteredTransactions() -> [Transaction] {
        let resolver = monthStartStore.resolver()
        let range = dateRange(resolver: resolver)

        var txs = store.transactions.filter { tx in
            tx.date >= range.start && tx.date <= range.end
        }

        switch filterType {
        case 1: txs = txs.filter { $0.type == .expense }
        case 2: txs = txs.filter { $0.type == .income }
        default: break
        }

        return txs
    }

    private func dateRange(resolver: MonthStartResolver) -> (start: Date, end: Date) {
        let now = Date()
        switch periodSelection {
        case 0:
            let range = resolver.monthRange(for: now)
            return (range.lowerBound, range.upperBound)
        case 1:
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            let range = resolver.monthRange(for: lastMonth)
            return (range.lowerBound, range.upperBound)
        case 2:
            // カスタム: customTo の終わりを日末に
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: customTo) ?? customTo
            return (customFrom, endOfDay)
        default:
            let range = resolver.monthRange(for: now)
            return (range.lowerBound, range.upperBound)
        }
    }

    private func periodTitle() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "ja_JP")

        switch periodSelection {
        case 0:
            dateFormatter.dateFormat = "yyyy年M月"
            return dateFormatter.string(from: Date())
        case 1:
            dateFormatter.dateFormat = "yyyy年M月"
            let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
            return dateFormatter.string(from: lastMonth)
        case 2:
            dateFormatter.dateFormat = "yyyy/M/d"
            return "\(dateFormatter.string(from: customFrom)) 〜 \(dateFormatter.string(from: customTo))"
        default:
            return ""
        }
    }

    // MARK: - 回数管理

    private func currentMonthKey() -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM"
        return df.string(from: Date())
    }

    private func incrementExportCount() {
        let key = currentMonthKey()
        let newCount = exportCount + 1
        exportCountRaw = "\(key):\(newCount)"
    }

    // MARK: - ヘルパー

    @ViewBuilder
    private func premiumBadge(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .foregroundStyle(.orange)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

// MARK: - ShareSheet（UIActivityViewController）

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
