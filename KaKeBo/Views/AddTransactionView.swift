//
//  Views/AddTransactionView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI

struct AddTransactionView: View {
    @EnvironmentObject var store: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    
    @State private var date: Date = Date()
    @State private var amount: Int = 0
    @State private var type: TransactionType = .expense
    @State private var memo: String = ""
    @State private var selectedCategoryId: UUID?
    
    // ▼ キーボード可視状態
    @State private var isKeyboardVisible = false
    // ▼ メモのフォーカス管理（キーボードの「閉じる」ボタン用）
    @FocusState private var memoFocused: Bool
    @State private var showCustomKeypad = true
    @State private var keypadHeight: CGFloat = 0
    @StateObject private var kb = KeyboardHeightReader()
    
    init(
        defaultCategoryId: UUID? = nil,
        defaultAmount: Int? = nil,
        defaultDate: Date? = nil,
        defaultType: TransactionType = .expense,
        defaultMemo: String? = nil
    ) {
        _selectedCategoryId = State(initialValue: defaultCategoryId)
        _amount = State(initialValue: defaultAmount ?? 0)
        _date   = State(initialValue: defaultDate ?? Date())
        _type   = State(initialValue: defaultType)
        _memo   = State(initialValue: defaultMemo ?? "")
    }
    
    var body: some View {
        NavigationStack {
            contentScroll
                .background(bgGradient.ignoresSafeArea())   // ← 重い式を外出し
                .navigationTitle("新規追加")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                // ▼ キーボードが見えてない時だけ電卓を出す
                .safeAreaInset(edge: .bottom) {
                    if showCustomKeypad {
                        NumericKeypad(
                            amount: $amount,
                            maxDigits: 9,
                            style: .attached,
                            isIncome: type == .income,
                            sizeScale: 0.85,
                            preferredHeightRatio: 0.33,
                            onHeightChange: { h in keypadHeight = h }  // ← ここで高さ受け取り
                        )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showCustomKeypad {
                        // ツールバーと同じ見た目にしたければ、共通化したボタンを使う
                        CloseKeyboardButton {
                            showCustomKeypad = false
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, keypadHeight + 8)  // ← キーボードの“上”に浮かせる
                    }
                }
                // システムキーボード時の「閉じる」をツールバー無しで重ねる
                .overlay(alignment: .bottomTrailing) {
                    // メモにフォーカス & キーボードが出ている時のみ表示
                    if memoFocused && kb.height > 0 {
                        CloseKeyboardButton {
                            memoFocused = false       // ← システムKBを閉じる
                            showCustomKeypad = false  // ← 念のため自作も閉じる
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, 8) // “キーボードの上” に浮かせる
                        .animation(.easeInOut(duration: 0.2), value: kb.height)
                    }
                }
                // ▼ システムキーボードが出たら自作キーボードは閉じる（メモ編集などのとき）
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isKeyboardVisible = true
                        showCustomKeypad = false
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isKeyboardVisible = false
                    }
                }
        }
    }
    
    // MARK: - 分割ビュー
    
    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 18) {
                metaSection.luxCard()
                
                CategorySelector(selectedCategoryId: $selectedCategoryId)
                    .environmentObject(store)
                
                Spacer(minLength: showCustomKeypad ? 60 : 0) // 電卓に重ならないよう余白
            }
            .padding(.top, 12)
            .padding(.horizontal)
        }
    }
    
    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            TypePillSelector(type: $type)
            // ▼ 日付
            VStack(alignment: .leading, spacing: 6) {
                Text("日付")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                DatePicker("", selection: $date, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "ja_JP"))
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // ▼ 金額入力欄
            VStack(alignment: .leading, spacing: 6) {
                Text("金額").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                
                // 疑似入力欄
                HStack {
                    Spacer()
                    Text(currency(amount))
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2))
                )
                .contentShape(Rectangle())                  // 余白までタップ可
                .onTapGesture {
                    // メモのフォーカスを外してシステムKBを閉じる → 自作キーパッドを出す
                    memoFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) { showCustomKeypad = true }
                }
                .accessibilityAddTraits(.isButton)
            }
            // ▼ メモ入力欄
            VStack(alignment: .leading, spacing: 6) {
                Text("メモ（任意）")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("例：昼食／スタバ など", text: $memo)
                    .textFieldStyle(.roundedBorder)
                    .focused($memoFocused) // ← フォーカス監視
            }
        }
    }
    
    // 通貨整形
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
    
    private var bgGradient: LinearGradient {
        let colors: [Color] = (scheme == .dark)
        ? [Color.black, Color(white: 0.15)]
        : [Color(white: 0.98), Color(white: 0.94)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    private var keypadBar: some View {
        // ここもネストを避けて型を軽く
        let barBackground: AnyView = {
            if scheme == .dark {
                return AnyView(Color(white: 0.08).opacity(0.95))
            } else {
                return AnyView(Rectangle().fill(.regularMaterial))
            }
        }()
        
        return NumericKeypad(amount: $amount, maxDigits: 9, isIncome: type == .income)
            .padding(.top, 8)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(barBackground)
            .overlay(Divider(), alignment: .top)
            .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            let isEnabled = !(store.categories.isEmpty || amount == 0 || selectedCategoryId == nil)
            
            SaveButton(isEnabled: isEnabled) {
                save()
            }
        }
    }
    
    // MARK: - Actions
    
    private func save() {
        guard
            let selId = selectedCategoryId,
            let chosen = store.categories.first(where: { $0.id == selId }),
            amount > 0
        else { return }
        
        let tx = Transaction(
            date: date,
            amount: amount,
            type: type,
            memo: memo,
            categoryId: chosen.id
        )
        store.addTransaction(tx)
        dismiss()
    }
}


struct SaveButton: View {
    let isEnabled: Bool
    let action: () -> Void
    
    var body: some View {
        if isEnabled {
            Button("保存", action: action)
                .buttonStyle(.borderedProminent)  // 有効 = 青
        } else {
            Button("保存", action: {})
                .buttonStyle(.bordered)
                .disabled(true)
        }
    }
}

struct CloseKeyboardButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("閉じる", systemImage: "keyboard.chevron.compact.down")
                .imageScale(.medium)
                .font(.body.weight(.semibold))
                .padding(.vertical, 9)
                .padding(.horizontal, 13)
                .frame(minHeight: 42)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous) // 14 → 16
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())                           // 余白もヒット領域に
        .shadow(color: .black.opacity(0.14), radius: 12, y: 3) // 少しだけ強めに
    }
}
