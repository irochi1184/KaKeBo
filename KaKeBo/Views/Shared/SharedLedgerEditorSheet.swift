//
//  Views/Shared/SharedLedgerEditorSheet.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/27.
//

import SwiftUI
import CloudKit
import UIKit

struct SharedLedgerEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: SharedLedgerStore
    @EnvironmentObject var dataStore: DataStore
    
    /// nil のときは「新規作成」モード
    let ledger: SharedLedger?
    
    @State private var name: String
    /// SF Symbols の systemName を保持
    @State private var icon: String
    /// 実際の編集は Color で行い、保存時に Hex に変換
    @State private var color: Color
    // 新規作成時のコピーオプション
    @State private var copyPersonalCategories = true
    @State private var copyPersonalTransactions = false
    @State private var isSaving = false
    
    // 候補アイコン（必要に応じて増やしてOK）
    private static let symbolCandidates: [String] = [
        "wallet.pass", "yensign.circle", "yensign.circle.fill",
        "creditcard", "creditcard.fill",
        "cart", "cart.fill",
        "bag", "bag.fill",
        "house", "house.fill",
        "building.2", "building.2.fill",
        "tram.fill", "airplane",
        "heart.fill", "heart.circle.fill",
        "person.2", "person.2.fill",
        "gift.fill", "fork.knife",
        "fuelpump.fill"
    ]
    
    init(ledger: SharedLedger?) {
        self.ledger = ledger
        _name  = State(initialValue: ledger?.name ?? "")
        _icon  = State(initialValue: ledger?.icon ?? "wallet.pass")
        _color = State(
            initialValue: Self.color(fromHex: ledger?.colorHex ?? "#34C759")
        )
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("家計簿名") {
                    TextField("例）生活費", text: $name)
                }
                
                Section("アイコン") {
                    iconPickerSection
                }
                
                Section("カラー") {
                    colorPickerSection
                }

                Section("iCloudについて") {
                    Label("共有家計簿の作成・共有にはiCloudが必要です", systemImage: "icloud")
                        .font(.subheadline.weight(.semibold))
                    Text("iCloudの空き容量が不足していると、共有の作成や招待リンクの発行に失敗する場合があります。事前に容量をご確認ください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if ledger == nil {
                    Section("個人用家計簿からコピー") {
                        Toggle("カテゴリをコピーする", isOn: $copyPersonalCategories)
                        Toggle("取引をコピーする", isOn: $copyPersonalTransactions)
                        
                        if copyPersonalTransactions {
                            Text("※ 現在の個人用家計簿の全ての取引が、この共有家計簿にコピーされます。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(ledger == nil ? "共有家計簿を作成" : "共有家計簿を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await saveLedger()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text(ledger == nil ? "作成" : "保存")
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
        .overlay {
            if isSaving {
                LoadingOverlayView(
                    title: "読み込み中",
                    message: ledger == nil ? "共有家計簿を作成しています…" : "共有家計簿を保存しています…"
                )
            }
        }
    }

    private func saveLedger() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let hex = Self.hex(from: color)

        if let ledger {
            await store.updateLedger(
                ledger,
                name: trimmedName,
                icon: icon,
                colorHex: hex
            )
        } else if let newLedger = await store.createLedger(
            name: trimmedName,
            icon: icon,
            colorHex: hex
        ) {
            store.startInitialCopy(
                from: dataStore,
                to: newLedger,
                copyCategories: copyPersonalCategories,
                copyTransactions: copyPersonalTransactions
            )
        }

        dismiss()
    }
    
    // MARK: - アイコン選択 UI
    
    @ViewBuilder
    private var iconPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 候補 SF Symbols の横スクロール
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.symbolCandidates, id: \.self) { symbol in
                        Button {
                            icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(
                                            icon == symbol
                                            ? color
                                            : Color.secondary.opacity(0.3),
                                            lineWidth: icon == symbol ? 2 : 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // 選択中アイコンのプレビュー
            HStack(spacing: 10) {
                Text("選択中:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                
                Spacer()
            }
        }
    }
    
    // MARK: - カラー選択 UI
    
    @ViewBuilder
    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ColorPicker("カラー", selection: $color, supportsOpacity: false)
                
                Spacer()
                
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(color)
                    .frame(width: 40, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }
    
    // MARK: - Color <-> Hex 変換ヘルパ
    
    private static func color(fromHex hex: String) -> Color {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let hexString = cleaned.hasPrefix("#") ? String(cleaned.dropFirst()) : cleaned
        
        guard hexString.count == 6,
              let value = Int(hexString, radix: 16) else {
            return Color.accentColor
        }
        
        let r = Double((value >> 16) & 0xFF) / 255.0
        let g = Double((value >> 8) & 0xFF) / 255.0
        let b = Double(value & 0xFF) / 255.0
        
        return Color(red: r, green: g, blue: b)
    }
    
    private static func hex(from color: Color) -> String {
#if os(iOS)
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
#else
        // iOS 以外はとりあえずアクセントカラーを返す
        return "#34C759"
#endif
    }
}
