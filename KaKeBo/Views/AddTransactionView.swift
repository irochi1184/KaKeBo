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
    
    // MARK: - States
    @State private var date: Date = Date()
    @State private var amount: Int = 0
    @State private var type: TransactionType = .expense
    @State private var memo: String = ""
    @State private var selectedCategoryId: UUID?
    
    // キーボード／UI
    @State private var isKeyboardVisible = false
    @FocusState private var memoFocused: Bool
    @State private var showCustomKeypad = true
    @State private var keypadHeight: CGFloat = 0
    @StateObject private var kb = KeyboardHeightReader()
    @State private var showAddCategory = false
    
    // ★ レシートスキャン表示フラグ
    @State private var showReceiptScanner = false
    
    // MARK: - Prefill (レシートや外部から)
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
    private var keypadScale: CGFloat { isSmallPhone ? 0.86 : 0.85 }
    private var keypadHeightRatio: CGFloat { isSmallPhone ? 0.30 : 0.33 }
    private var keypadLift: CGFloat { isSmallPhone ? 34 : 0 }
    private var extraButtonLift: CGFloat { isSmallPhone ? 100 : 10 }
    private var safeBottomInset: CGFloat {
        UIApplication.shared.activeKeyWindow?.safeAreaInsets.bottom ?? 0
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            contentScroll
                .background(bgGradient.ignoresSafeArea())
                .navigationTitle("新規追加")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
            
            // カスタム電卓
                .safeAreaInset(edge: .bottom) {
                    if showCustomKeypad {
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
                            .padding(.bottom, safeBottomInset)
                        }
                        .offset(y: -keypadLift)
                    }
                }
            
            // 自作キーパッドの閉じる
                .overlay(alignment: .bottomTrailing) {
                    if showCustomKeypad {
                        CloseKeyboardButton { showCustomKeypad = false }
                            .padding(.trailing, 12)
                            .padding(.bottom,
                                     max(8, (keypadHeight - keypadLift) + extraButtonLift + safeBottomInset)
                            )
                    }
                }
            
            // システムキーボード時の閉じる
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
            
            // ★ レシートスキャンのシート
                .sheet(isPresented: $showReceiptScanner) {
                    NavigationStack {
                        ReceiptScanView { recognized in
                            // 解析してフィールドへ反映（ReceiptParser.swift を利用）
                            let r = ReceiptParser.parse(recognized)
                            if let v = r.total { amount = v }
                            if let d = r.date  { date   = d }
                            if let m = r.merchant, m.isEmpty == false {
                                // 既にメモがあれば追記、なければ置換
                                memo = memo.isEmpty ? m : "\(memo) \(m)"
                            }
                            // 金額編集しやすいよう自作キーパッドを出しておく
                            showCustomKeypad = true
                        }
                        .navigationTitle("レシート読み取り")
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
            
            // 日付
            VStack(alignment: .leading, spacing: 6) {
                JapaneseDatePickerRow(date: $date)
            }
            
            // 金額
            VStack(alignment: .leading, spacing: 6) {
                Text("金額").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
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
                    memoFocused = false
                    withAnimation(.easeInOut(duration: 0.2)) { showCustomKeypad = true }
                }
                .accessibilityAddTraits(.isButton)
            }
            
            // メモ
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
    
    // MARK: - ヘルパ
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
    
    // MARK: - Toolbar（保存の横にカメラ）
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") { dismiss() }
        }
        // ★ カメラ（レシート読取）ボタン
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                // キーボードを閉じてからスキャナへ
                memoFocused = false
                showCustomKeypad = false
                showReceiptScanner = true
            } label: {
                Label("レシート", systemImage: "doc.text.viewfinder")
            }
        }
        // 保存ボタン
        ToolbarItem(placement: .topBarTrailing) {
            let isEnabled = !(store.categories.isEmpty || amount == 0 || selectedCategoryId == nil)
            SaveButton(isEnabled: isEnabled, accent: themeStore.theme.accentColor(for: scheme)) {
                save()
            }
        }
    }
    
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

// MARK: - Buttons & Utils
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

private extension UIApplication {
    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
