//
//  WatchHomeView.swift
//  KaKeBoWatch
//
//  Watch アプリのメイン画面
//  - 当月サマリー表示
//  - テンプレートからの素早い入力
//

import SwiftUI

struct WatchHomeView: View {
    @EnvironmentObject var session: WatchSessionManager

    var body: some View {
        NavigationStack {
            List {
                // 当月サマリー
                Section {
                    SummaryRow(label: "今月の支出", amount: session.monthExpense, color: .red)
                    SummaryRow(label: "今月の収入", amount: session.monthIncome, color: .green)
                    SummaryRow(label: "収支", amount: session.monthIncome - session.monthExpense, color: .primary)
                }

                // 今日の支出
                Section {
                    HStack {
                        Text("今日の支出")
                            .font(.caption)
                        Spacer()
                        Text("¥\(session.todayExpense)")
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                }

                // よく使うテンプレートから入力
                Section("かんたん入力") {
                    if session.templates.isEmpty {
                        Text("iPhoneで「よく使う取引」を登録するとここに表示されます")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.templates.prefix(5)) { template in
                            NavigationLink {
                                TemplateConfirmView(template: template)
                                    .environmentObject(session)
                            } label: {
                                TemplateRow(template: template)
                            }
                        }
                    }
                }

                // カスタム入力
                Section {
                    NavigationLink {
                        CustomInputView()
                            .environmentObject(session)
                    } label: {
                        Label("金額を入力", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("KaKeBo")
        }
        .onAppear {
            session.requestSync()
        }
    }
}

// MARK: - サマリー行

private struct SummaryRow: View {
    let label: String
    let amount: Int
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
            Spacer()
            Text("¥\(amount)")
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
    }
}

// MARK: - テンプレート行

private struct TemplateRow: View {
    let template: WatchTemplate

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: template.categorySymbol)
                .font(.caption)
                .foregroundStyle(Color.fromHex(template.categoryColorHex))
            VStack(alignment: .leading, spacing: 2) {
                Text(template.title)
                    .font(.caption)
                    .lineLimit(1)
                Text("¥\(template.amount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
