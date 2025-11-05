//
//  Views/EditTransactionView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/10.
//

import SwiftUI
import UIKit

struct EditTransactionView: View {
    @EnvironmentObject var store: DataStore
    @EnvironmentObject var themeStore: ThemeStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    
    // 元データ
    let transaction: Transaction
    
    // 編集ステート（Add と同構成）
    @State private var date: Date
    @State private var amount: Int
    @State private var type: TransactionType
    @State private var memo: String
    @State private var selectedCategoryId: UUID?
    
    // キーボード制御（Add と揃える）
    @State private var isKeyboardVisible = false
    @FocusState private var memoFocused: Bool
    @State private var showCustomKeypad = true          // 初期表示：自作キーパッド表示
    @State private var keypadHeight: CGFloat = 0        // 自作キーパッド高さ（閉じるボタン位置調整用）
    @StateObject private var kb = KeyboardHeightReader()
    @State private var showAddCategory = false
    
    init(transaction: Transaction) {
        self.transaction = transaction
        _date = State(initialValue: transaction.date)
        _amount = State(initialValue: transaction.amount)
        _type = State(initialValue: transaction.type)
        _memo = State(initialValue: transaction.memo)
        _selectedCategoryId = State(initialValue: transaction.categoryId)
    }
    
    // 実効的に必要な下パディング（overlay配置のキーパッドと重ならないため）
    private var contentBottomPadding: CGFloat {
        guard showCustomKeypad else { return 0 }
        // キーパッドの実高さ ー 見た目の持ち上げ量 + 余白 + セーフエリア
        return max(0, (keypadHeight - keypadLift)) + 16 + safeBottomInset
    }
    
    // ===== 小画面（SE2等）だけの調整値 =====
    private var isSmallPhone: Bool {
#if os(iOS)
        UIScreen.main.bounds.height <= 667
#else
        false
#endif
    }
    // AddTransactionView を参考に：サイズは少し大きめ、位置は上にずらす
    private var keypadScale: CGFloat { isSmallPhone ? 0.86 : 0.85 }       // 少し大きく
    private var keypadHeightRatio: CGFloat { isSmallPhone ? 0.30 : 0.33 } // 高さも戻す
    private var keypadLift: CGFloat { isSmallPhone ? 34 : 0 }             // 上方向に持ち上げ
    private var extraButtonLift: CGFloat { isSmallPhone ? 100 : 10 }      // 「閉じる」ボタンをさらに上へ
    
    // セーフエリア下端
    private var safeBottomInset: CGFloat {
        UIApplication.shared.activeKeyWindow?.safeAreaInsets.bottom ?? 0
    }
    
    var body: some View {
        NavigationStack {
            contentScroll
                .background(bgGradient.ignoresSafeArea())
                .navigationTitle("取引を編集")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
            // ▼ safeAreaInsetは使わず、overlayで下部配置（白抜け防止のため下地を敷く）
                .overlay(alignment: .bottom) {
                    if showCustomKeypad {
                        ZStack(alignment: .bottom) {
                            // 下地：透明領域でマテリアルが白発光するのを防ぐ
                            Rectangle()
                                .fill(themeStore.theme.backgroundColor(for: scheme))
                                .frame(height: safeBottomInset + 100)
                                .ignoresSafeArea(edges: .bottom)
                            
                            NumericKeypad(
                                amount: $amount,
                                maxDigits: 9,
                                style: .attached,
                                isIncome: type == .income,
                                sizeScale: keypadScale,
                                preferredHeightRatio: keypadHeightRatio,
                                onHeightChange: { h in keypadHeight = h }
                            )
                            // ホームインジケータ分を確保した上で、見た目だけ上へ
                            .padding(.bottom, safeBottomInset)
                            .offset(y: -keypadLift)
                        }
                    }
                }
            // 右下・独立した「閉じる」ボタン（キーパッドの表示テキストに被らないよう高め）
                .overlay(alignment: .bottomTrailing) {
                    if showCustomKeypad {
                        CloseKeyboardButton {
                            showCustomKeypad = false
                        }
                        .padding(.trailing, 12)
                        .padding(.bottom, max(
                            8,
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
            // ▼ システムKBが出たら自作は閉じる（メモ編集などのとき）
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
    
    // MARK: - Sections
    
    private var contentScroll: some View {
        ScrollView {
            VStack(spacing: 18) {
                metaSection.luxCard()
                
                CategorySelector(
                    selectedCategoryId: $selectedCategoryId,
                    onTapAdd: { showAddCategory = true }
                )
                .environmentObject(store)
                
                Spacer(minLength: showCustomKeypad ? (isSmallPhone ? 12 : 20) : 0)
            }
            .padding(.top, 12)
            .padding(.horizontal)
            // ← ここがポイント：キーパッド分だけスクロール領域に実パディングを付与
            .padding(.bottom, contentBottomPadding)
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
            // 種別トグル
            TypePillSelector(type: $type)
            
            // 日付
            VStack(alignment: .leading, spacing: 6) {
                JapaneseDatePickerRow(date: $date)
            }
            
            // 金額（疑似入力欄・タップで自作キーボード）
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
                    // メモのフォーカスを外してシステムKBを閉じる → 自作キーパッドを出す
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
    
    // MARK: - 共通見た目
    
    private var bgGradient: LinearGradient {
        let colors: [Color] = (scheme == .dark)
        ? [Color.black, Color(white: 0.15)]
        : [Color(white: 0.98), Color(white: 0.94)]
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }
    
    private func currency(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return "¥" + (f.string(from: n as NSNumber) ?? "\(n)")
    }
    
    // MARK: - Toolbar（Add と統一：削除と保存を独立して配置）
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("閉じる") { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(role: .destructive) {
                performDelete()
            } label: {
                Label("削除", systemImage: "trash")
            }
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
        guard let catId = selectedCategoryId else { return }
        var edited = transaction
        edited.date = date
        edited.amount = amount
        edited.type = type
        edited.memo = memo
        edited.categoryId = catId
        
        store.upsertTransaction(edited)
        dismiss()
    }
    
    private func performDelete() {
        store.deleteTransactions(with: [transaction.id])
        dismiss()
    }
}

// UIWindow / セーフエリア取得のユーティリティ
private extension UIApplication {
    var activeKeyWindow: UIWindow? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
