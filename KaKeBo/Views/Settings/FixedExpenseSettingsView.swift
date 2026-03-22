//
//  Views/Settings/FixedExpenseSettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/18.
//

import SwiftUI

struct FixedExpenseSettingsView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var purchase: PurchaseManager
    @State private var templates: [FixedExpenseTemplate] = []
    @State private var editing: FixedExpenseTemplate? = nil
    @State private var isAdding = false
    @State private var showDeleteAlert: FixedExpenseTemplate? = nil
    
    @State private var quickAddExpanded = false
    @State private var showConfirm = false
    @State private var confirmMessage = ""
    @State private var showPaywall = false
    
    // 無料プランで登録可能な数
    private let freeLimit = 5
    
    var body: some View {
        List {
            // クイック追加
            Section {
                DisclosureGroup(isExpanded: $quickAddExpanded) {
                    QuickFixedButtons(
                        onPick: { tpl in
                            // 制限チェック（クイック追加）
                            if canAddMore {
                                templates.append(tpl)
                                saveTemplates()
                            } else {
                                showPaywall = true
                            }
                        }
                    )
                    .padding(.vertical, 8)
                } label: {
                    Label("クイック追加", systemImage: "plus.circle")
                }
                // 無料ユーザー向けロック説明
                if !purchase.isPremiumActive {
                    Text("無料プランでは固定費は最大 \(freeLimit) 件まで。\n6件目以降を登録するにはプレミアムプランへの加入が必要です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("固定費の合計", systemImage: "yensign.circle.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(yen(totalActiveAmount))
                            .font(.headline.weight(.bold))
                    }

                    Text("有効にしている固定費\(activeTemplatesCount)件を合計しています。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "固定費は未登録",
                        systemImage: "yensign.circle",
                        description: Text("右上の＋やクイック追加から登録してください")
                    )
                } else {
                    ForEach(templates) { t in
                        HStack {
                            VStack(alignment:.leading, spacing: 4) {
                                HStack(spacing:8) {
                                    Circle().fill(colorFor(categoryId: t.categoryId).opacity(0.15))
                                        .frame(width: 22, height: 22)
                                        .overlay(Image(systemName: iconFor(categoryId: t.categoryId))
                                            .foregroundStyle(colorFor(categoryId: t.categoryId)))
                                    Text(t.title).font(.subheadline.weight(.semibold))
                                    if !t.isActive {
                                        Text("無効").font(.caption2).padding(.horizontal,6).padding(.vertical,2)
                                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                                    }
                                }
                                HStack(spacing:6) {
                                    Text("金額 \(yen(t.amount))").font(.caption).foregroundStyle(.secondary)
                                    Text("毎月 \(dayText(t.dayOfMonth))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: .init(
                                get: { t.isActive },
                                set: { newVal in
                                    if let i = templates.firstIndex(where: { $0.id == t.id }) {
                                        templates[i].isActive = newVal
                                        saveTemplates()
                                    }
                                }
                            ))
                            .labelsHidden()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editing = t }
                        .swipeActions {
                            Button { editing = t } label: {
                                Label("編集", systemImage: "pencil")
                            }.tint(.blue)
                            
                            Button(role: .destructive) {
                                showDeleteAlert = t
                            } label: { Label("削除", systemImage: "trash") }
                        }
                    }
                    .onDelete { idx in
                        templates.remove(atOffsets: idx); saveTemplates()
                    }
                    .onMove { from, to in
                        templates.move(fromOffsets: from, toOffset: to); saveTemplates()
                    }
                }
            }
            
            // 今月分の自動計上（到来分）を実行
            Section {
                Button {
                    let beforeCount = store.transactions.count
                    store.applyFixedExpensesForCurrentMonth()
                    let afterCount = store.transactions.count
                    let diff = afterCount - beforeCount
                    
                    confirmMessage = (diff > 0)
                    ? "\(diff)件の固定費を自動計上しました"
                    : "今月の未計上分はありませんでした"
                    
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(diff > 0 ? .success : .warning)
                    showConfirm = true
                } label: {
                    Label("今月の未計上分を自動計上", systemImage: "checkmark.circle")
                }
            }
            .alert("自動計上", isPresented: $showConfirm) {
                Button("OK", role: .cancel) {}
            } message: { Text(confirmMessage) }
        }
        .listRowBackground(FlatListRowBackground(appliesFlatBorder: false))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton().disabled(templates.isEmpty)
                Button {
                    // 右上＋ の入口でも制限チェック
                    if canAddMore {
                        isAdding = true
                    } else {
                        showPaywall = true
                    }
                } label: { Image(systemName: "plus") }
            }
        }
        .onAppear { loadTemplates() }
        .sheet(item: $editing) { t in
            FixedExpenseEditorView(
                initial: t,
                categories: store.categories,
                onSave: { tpl in
                    if let i = templates.firstIndex(where: { $0.id == t.id }) {
                        templates[i] = tpl
                        saveTemplates()
                    }
                }
            )
        }
        .sheet(isPresented: $isAdding) {
            FixedExpenseEditorView(
                initial: nil,
                categories: store.categories,
                onSave: { tpl in
                    // エディタからの保存でも制限チェック
                    if canAddMore {
                        templates.append(tpl); saveTemplates()
                    } else {
                        // 画面は閉じるが、保存はしない → すぐペイウォールへ
                        saveTemplates()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showPaywall = true }
                    }
                }
            )
        }
        .alert("固定費を削除しますか？", isPresented: .init(
            get: { showDeleteAlert != nil },
            set: { if !$0 { showDeleteAlert = nil } }
        )) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let t = showDeleteAlert {
                    templates.removeAll { $0.id == t.id }
                    saveTemplates()
                    showDeleteAlert = nil
                }
            }
        } message: {
            Text("この操作は固定費テンプレートだけを削除します。既に計上済みの家計簿データは残ります。")
        }
        // プレミアム誘導
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(accent: .accentColor)
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
    }
    
    // MARK: - 制限判定
    private var canAddMore: Bool {
        if purchase.isPremiumActive { return true }
        return templates.count < freeLimit
    }

    private var totalActiveAmount: Int {
        templates.filter { $0.isActive }.map { $0.amount }.reduce(0, +)
    }

    private var activeTemplatesCount: Int {
        templates.filter { $0.isActive }.count
    }

    // MARK: - Storage
    private func loadTemplates() {
        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: [DataStore.fixedTemplatesKey])
        let data = defaults.migratedData(forKey: DataStore.fixedTemplatesKey) ?? Data()
        templates = (try? JSONDecoder().decode([FixedExpenseTemplate].self, from: data)) ?? []
    }
    private func saveTemplates() {
        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: [DataStore.fixedTemplatesKey])
        defaults.set(try? JSONEncoder().encode(templates), forKey: DataStore.fixedTemplatesKey)
    }
    
    // MARK: - Helpers
    private func yen(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
    private func dayText(_ d: Int) -> String { d == 0 ? "月末" : "\(d)日" }
    private func colorFor(categoryId: UUID) -> Color {
        store.categories.first(where: { $0.id == categoryId })?.color ?? .secondary
    }
    private func iconFor(categoryId: UUID) -> String {
        store.categories.first(where: { $0.id == categoryId })?.symbolName ?? "tag"
    }
}

// クイック追加（よくある固定費）
private struct QuickFixedButtons: View {
    let onPick: (FixedExpenseTemplate) -> Void
    @EnvironmentObject var store: DataStore
    
    var body: some View {
        let candidates: [(String, Int, Int, String)] = [
            // title, amount, day, SF Symbol
            ("家賃",        80000,  1, "house.fill"),
            ("駐車場",      12000,  1, "parkingsign.circle.fill"),
            ("電気代",       7000, 25, "bolt.fill"),
            ("ガス代",       6000, 25, "flame.fill"),
            ("水道代",       5000, 25, "drop.fill"),
            ("インターネット", 5000,  1, "wifi"),
            ("携帯電話",      7000,  1, "iphone.gen3"),
            ("サブスク(A)",    980,  1, "play.circle.fill"),
            ("サブスク(B)",   1200,  1, "music.note.list"),
            ("保険料",      12000, 27, "shield.fill"),
        ]
        // 最初の支出カテゴリを既定に（利用者が後から編集できる）
        let defaultCat = store.categories.first?.id
        
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(candidates, id: \.0) { (title, amount, day, symbol) in
                Button {
                    guard let catId = defaultCat else { return }
                    onPick(FixedExpenseTemplate(
                        title: title,
                        amount: amount,
                        dayOfMonth: day,
                        categoryId: catId,
                        memo: nil,
                        isActive: true
                    ))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .foregroundStyle(.white)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.blue.gradient)) // 見た目を統一
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.caption.weight(.semibold))
                            Text("¥\(amount)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
