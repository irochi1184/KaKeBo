//
//  Views/AddTransactionView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import SwiftUI
import UIKit

struct AddTransactionView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
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
    @State private var showAddCategory = false
    
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
    
    // ===== 小画面（SE2等）だけの調整値 =====
    private var isSmallPhone: Bool {
#if os(iOS)
        UIScreen.main.bounds.height <= 667
#else
        false
#endif
    }
    // ← ここだけ触れば微調整しやすい
    private var keypadScale: CGFloat { isSmallPhone ? 0.86 : 0.85 }       // 少し大きく戻す
    private var keypadHeightRatio: CGFloat { isSmallPhone ? 0.30 : 0.33 } // 高さも戻す
    private var keypadLift: CGFloat { isSmallPhone ? 34 : 0 }             // さらに上へ
    private var extraButtonLift: CGFloat { isSmallPhone ? 100 : 10 }      // 閉じるボタンを上へ
    // セーフエリア下端（Environment未使用の汎用取得）
    private var safeBottomInset: CGFloat {
        UIApplication.shared.activeKeyWindow?.safeAreaInsets.bottom ?? 0
    }
    
    var body: some View {
        NavigationStack {
            contentScroll
                .background(bgGradient.ignoresSafeArea())
                .navigationTitle("新規追加")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
            // ▼ キーボードが見えてない時だけ電卓を出す
                .safeAreaInset(edge: .bottom) {
                    if showCustomKeypad {
                        // ZStackに包み、見た目位置だけ上にリフト
                        ZStack {
                            NumericKeypad(
                                amount: $amount,
                                maxDigits: 9,
                                style: .attached,
                                isIncome: type == .income,
                                sizeScale: keypadScale,
                                preferredHeightRatio: keypadHeightRatio,
                                onHeightChange: { h in keypadHeight = h }
                            )
                            // ↓ 念のため下端のセーフエリア分を内部に確保した上で持ち上げる
                            .padding(.bottom, safeBottomInset)
                        }
                        .offset(y: -keypadLift) // ← 小画面だけ持ち上げ
                    }
                }
            // 右下・独立した「閉じる」ボタン（キーパッドの表示テキストに被らないよう高め）
                .overlay(alignment: .bottomTrailing) {
                    if showCustomKeypad {
                        CloseKeyboardButton {
                            showCustomKeypad = false
                        }
                        .padding(.trailing, 12)
                        // キーパッドの上面からさらに持ち上げ（セーフエリアも考慮）
                        .padding(.bottom, max(8,
                                              (keypadHeight - keypadLift) + extraButtonLift + safeBottomInset
                                             ))
                    }
                }
            // システムキーボード時の「閉じる」をツールバー無しで重ねる
                .overlay(alignment: .bottomTrailing) {
                    if memoFocused && kb.height > 0 {
                        CloseKeyboardButton {
                            memoFocused = false
                            showCustomKeypad = false
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, 8 + safeBottomInset)
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
                
                CategorySelector(
                    selectedCategoryId: $selectedCategoryId,
                    onTapAdd: { showAddCategory = true }
                )
                .environmentObject(store)
                
                // 小型画面では余白は控えめ（キーパッドが上がるため）
                Spacer(minLength: showCustomKeypad ? (isSmallPhone ? 20 : 60) : 0)
            }
            .padding(.top, 12)
            .padding(.horizontal)
        }
        .background(themeStore.theme.backgroundColor(for: scheme))
        .sheet(isPresented: $showAddCategory) {
            NavigationStack {
                CategoryEditorView(category: nil) { newCat in
                    selectedCategoryId = newCat.id
                }
                .environmentObject(store)
                .navigationTitle("カテゴリ追加")
            }
        }
    }
    
    private var metaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            TypePillSelector(type: $type)
            // ▼ 日付
            VStack(alignment: .leading, spacing: 6) {
                JapaneseDatePickerRow(date: $date)
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
                .contentShape(Rectangle())
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
                    .textFieldStyle(.plain)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(themeStore.theme.backgroundColor(for: scheme))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .focused($memoFocused)
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
            
            SaveButton(isEnabled: isEnabled, accent: themeStore.theme.accentColor(for: scheme)) {
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


/// 保存ボタン
struct SaveButton: View {
    let isEnabled: Bool
    let accent: Color
    let action: () -> Void
    
    var body: some View {
        if isEnabled {
            Button("保存", action: action)
                .buttonStyle(.borderedProminent)
                .tint(accent)
        } else {
            Button("保存", action: {})
                .buttonStyle(.bordered)
                .disabled(true)
        }
    }
}

/// 「閉じる」ボタン
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
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 0.8)
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.14), radius: 12, y: 3)
    }
}

/// UIWindow / セーフエリア取得のユーティリティ（Environment未使用で安全）
private extension UIApplication {
    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
