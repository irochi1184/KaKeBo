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
    @State private var selectedIconCategory: IconCategory = .shared

    private enum IconCategory: String, CaseIterable, Identifiable {
        case shared = "共有向け"
        case living = "暮らし"
        case shopping = "買い物"
        case moveAndTrip = "移動・旅行"
        case hobby = "趣味・学び"
        case health = "健康"
        case income = "収入"

        var id: String { rawValue }
    }

    private static let symbolsByCategory: [IconCategory: [String]] = [
        .shared: [
            "person.2.fill", "person.2", "person.3.fill", "person.3",
            "house.fill", "house", "building.2.fill", "building.2",
            "heart.fill", "heart.circle.fill", "calendar", "wallet.pass.fill",
            "wallet.pass", "creditcard.fill", "tray.full.fill", "list.bullet.clipboard.fill"
        ],
        .living: [
            "fork.knife", "cup.and.saucer.fill", "takeoutbag.and.cup.and.straw.fill",
            "lightbulb.fill", "drop.fill", "wifi", "house.fill", "sofa.fill",
            "washer.fill", "lamp.table.fill", "refrigerator.fill", "bed.double.fill",
            "pawprint.fill", "leaf.fill", "gift.fill", "sparkles"
        ],
        .shopping: [
            "cart.fill", "cart", "basket.fill", "bag.fill",
            "tag.fill", "creditcard.fill", "shippingbox.fill", "takeoutbag.and.cup.and.straw",
            "gift.fill", "ticket.fill", "storefront.fill", "barcode.viewfinder",
            "qrcode.viewfinder", "scissors", "tshirt.fill", "bag.badge.plus"
        ],
        .moveAndTrip: [
            "tram.fill", "car.fill", "bus.fill", "bicycle", "airplane",
            "ferry.fill", "fuelpump.fill", "suitcase.fill", "bed.double.fill", "map.fill",
            "mappin.circle.fill", "camera.fill", "building.columns.fill", "house.lodge.fill",
            "figure.walk", "figure.run"
        ],
        .hobby: [
            "gamecontroller.fill", "music.note.list", "tv.fill", "book.fill", "graduationcap.fill",
            "pencil.and.scribble", "paintbrush.pointed.fill", "camera.macro", "theatermasks.fill",
            "sportscourt.fill", "figure.badminton", "dumbbell.fill", "party.popper.fill",
            "birthday.cake.fill", "baseball.fill", "basketball.fill"
        ],
        .health: [
            "cross.case.fill", "stethoscope", "pills.fill", "bandage.fill", "heart.text.square.fill",
            "figure.walk.motion", "figure.cooldown", "figure.mind.and.body", "figure.strengthtraining.traditional",
            "face.smiling.fill", "sun.max.fill", "moon.stars.fill", "lungs.fill", "allergens.fill",
            "cross.fill", "bolt.heart.fill"
        ],
        .income: [
            "yensign.circle.fill", "yensign.circle", "banknote.fill", "wallet.pass.fill",
            "building.columns.fill", "creditcard.fill", "chart.line.uptrend.xyaxis", "briefcase.fill",
            "doc.text.fill", "calendar.badge.clock", "giftcard.fill", "sparkles.tv.fill",
            "dollarsign.circle.fill", "eurosign.circle.fill", "sterlingsign.circle.fill", "percent"
        ]
    ]
    
    init(ledger: SharedLedger?) {
        self.ledger = ledger
        _name  = State(initialValue: ledger?.name ?? "")
        _icon  = State(initialValue: ledger?.icon ?? "person.2.fill")
        _color = State(
            initialValue: Self.color(fromHex: ledger?.colorHex ?? "#34C759")
        )
        _selectedIconCategory = State(initialValue: Self.category(for: ledger?.icon ?? "person.2.fill"))
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
            Picker("アイコンカテゴリ", selection: $selectedIconCategory) {
                ForEach(IconCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                    ForEach(Self.symbolsByCategory[selectedIconCategory] ?? [], id: \.self) { symbol in
                        iconButton(for: symbol)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: 180)
            
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

    @ViewBuilder
    private func iconButton(for symbol: String) -> some View {
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

    private static func category(for icon: String) -> IconCategory {
        if let match = symbolsByCategory.first(where: { $0.value.contains(icon) })?.key {
            return match
        }
        return .shared
    }
}
