import SwiftUI

struct EmailImportSettingsView: View {
    @EnvironmentObject private var store: DataStore
    @EnvironmentObject private var purchase: PurchaseManager

    @State private var settings: EmailImportSettings = EmailImportSettings.load()
    @State private var senderInput: String = ""
    @State private var bodyInput: String = ""
    @State private var resultMessage: String? = nil
    @State private var showResultAlert = false
    @State private var showPaywall = false

    private let importer = EmailReceiptImportService()

    var body: some View {
        Form {
            if !purchase.isPremiumActive {
                Section {
                    Text("この機能はプレミアムプラン限定です。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button {
                        showPaywall = true
                    } label: {
                        Label("プレミアムを確認する", systemImage: "lock.open")
                    }
                }
            }

            Section {
                Text("登録したメールアドレスと一致した通知のみを取込対象にします。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("楽天Payの送信元メールアドレス", text: $settings.rakutenPaySender)
                    .textInputAutocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .onChange(of: settings.rakutenPaySender) { _, _ in saveSettings() }
                    .disabled(!purchase.isPremiumActive)

                TextField("JCBの送信元メールアドレス", text: $settings.jcbSender)
                    .textInputAutocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .onChange(of: settings.jcbSender) { _, _ in saveSettings() }
                    .disabled(!purchase.isPremiumActive)
            } header: {
                Text("対象メールアドレス")
            }

            Section {
                Picker("楽天Payのカテゴリ", selection: $settings.rakutenPayCategoryId) {
                    Text("未設定").tag(UUID?.none)
                    ForEach(store.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .onChange(of: settings.rakutenPayCategoryId) { _, _ in saveSettings() }
                .disabled(!purchase.isPremiumActive)

                Picker("JCBのカテゴリ", selection: $settings.jcbCategoryId) {
                    Text("未設定").tag(UUID?.none)
                    ForEach(store.categories) { category in
                        Text(category.name).tag(Optional(category.id))
                    }
                }
                .onChange(of: settings.jcbCategoryId) { _, _ in saveSettings() }
                .disabled(!purchase.isPremiumActive)
            } header: {
                Text("自動追加のカテゴリ")
            }

            Section {
                Text("iOSの制限により、メール本文は自動取得できません。通知メールをコピーして貼り付けてください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("送信元メールアドレス（任意）", text: $senderInput)
                    .textInputAutocapitalization(.none)
                    .keyboardType(.emailAddress)
                    .disabled(!purchase.isPremiumActive)

                TextEditor(text: $bodyInput)
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2))
                    )
                    .disabled(!purchase.isPremiumActive)

                Button {
                    handleImport()
                } label: {
                    Label("解析して取引追加", systemImage: "tray.and.arrow.down")
                }
                .disabled(!purchase.isPremiumActive || bodyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("メール通知の取り込み")
            } footer: {
                Text("同じ日付・金額・メモの取引がある場合は重複としてスキップします。")
                    .font(.footnote)
            }
        }
        .navigationTitle("メール通知の自動追加")
        .navigationBarTitleDisplayMode(.inline)
        .alert("取り込み結果", isPresented: $showResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(resultMessage ?? "")
        }
        .sheet(isPresented: $showPaywall) {
            PremiumPaywallView(accent: .accentColor)
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            settings = EmailImportSettings.load()
        }
    }

    private func saveSettings() {
        settings.save()
    }

    private func handleImport() {
        do {
            let result = try importer.importReceipts(
                text: bodyInput,
                senderInput: senderInput,
                store: store,
                settings: settings
            )
            resultMessage = result.message
            showResultAlert = true
        } catch {
            resultMessage = error.localizedDescription
            showResultAlert = true
        }
    }
}
