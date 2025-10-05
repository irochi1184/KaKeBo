//
//  Views/RecurringTodoSettingsView.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/02.
//

import SwiftUI

struct RecurringTodoSettingsView: View {
    @AppStorage("kakebo.recurring.templates") private var templatesData: Data = Data()
    
    @State private var templates: [RecurringTodoTemplate] = []
    @State private var newTitle: String = ""
    @State private var newDay: Int = 0   // 0=月末, 1...31
    
    @EnvironmentObject var store: DataStore
    @Environment(\.colorScheme) private var scheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                background // ← 重い式を外出し
                content    // ← 中身も外出し
            }
            .navigationTitle("テンプレート管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }           // ← ツールバーも分割
            .onAppear(perform: load)
        }
    }
    
    private var background: some View {
        let top = scheme == .dark ? Color.black : Color(white: 0.98)
        let bottom = scheme == .dark ? Color(white: 0.14) : Color(white: 0.94)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
    
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                
                AddTemplateCard(
                    newTitle: $newTitle,
                    newDay: $newDay,
                    onAdd: addTemplate
                )
                .padding(.horizontal)
                
                if templates.isEmpty {
                    EmptyStateCard().padding(.horizontal)
                } else {
                    VStack(spacing: 14) {
                        ForEach(templates) { tpl in
                            TemplateRowCard(
                                template: binding(for: tpl),
                                categories: store.categories,
                                onDelete: { deleteTemplate(tpl) }
                            )
                        }
                    }
                    .padding(.horizontal)
                }
                
                Spacer(minLength: 24)
            }
            .padding(.top, 16)
        }
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "checklist.checked")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 28, weight: .semibold))
                Text("毎月のToDo")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
            }
            Text("毎月自動で作成されるタスク。必要に応じて一時停止（トグル）やカテゴリ/金額のプリセットを設定できます。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
    
    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    // 明示的なキー計算で型推論を楽に
                    templates.sort { a, b in
                        let aDay: Int = (a.dayOfMonth == 0 ? 32 : a.dayOfMonth)
                        let bDay: Int = (b.dayOfMonth == 0 ? 32 : b.dayOfMonth)
                        if aDay != bDay { return aDay < bDay }
                        // isActive を先に（true を前へ）
                        let aActive = a.isActive ? 0 : 1
                        let bActive = b.isActive ? 0 : 1
                        return aActive < bActive
                    }
                    save()
                } label: {
                    Label("日付順に並べ替え", systemImage: "arrow.up.arrow.down")
                }
                
                Button(role: .destructive) {
                    let before = templates.count
                    templates.removeAll { !$0.isActive }
                    if templates.count != before { save() }
                } label: {
                    Label("停止中を一括削除", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
    
    private func load() {
        if templatesData.isEmpty {
            templates = []
        } else if let items = try? JSONDecoder().decode([RecurringTodoTemplate].self, from: templatesData) {
            templates = items
        }
    }
    private func save() {
        templatesData = (try? JSONEncoder().encode(templates)) ?? Data()
    }
    private func addTemplate() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        templates.append(.init(title: title, dayOfMonth: newDay, isActive: true))
        newTitle = ""; newDay = 0
        save()
    }
    private func deleteTemplate(_ tpl: RecurringTodoTemplate) {
        templates.removeAll { $0.id == tpl.id }
        save()
    }
    private func binding(for tpl: RecurringTodoTemplate) -> Binding<RecurringTodoTemplate> {
        Binding(
            get: { templates.first(where: { $0.id == tpl.id }) ?? tpl },
            set: { newVal in
                if let i = templates.firstIndex(where: { $0.id == tpl.id }) {
                    templates[i] = newVal
                    save()
                }
            }
        )
    }
    
    /// 追加用の上質なカード
    private struct AddTemplateCard: View {
        @Binding var newTitle: String
        @Binding var newDay: Int
        let onAdd: () -> Void
        @Environment(\.colorScheme) private var scheme
        
        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                Label("新規追加", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                
                HStack(spacing: 10) {
                    TextField("例：家賃の支払い", text: $newTitle)
                        .textInputAutocapitalization(.never)
                        .textFieldStyle(.roundedBorder)
                    
                    Picker("日付", selection: $newDay) {
                        Text("月末").tag(0)
                        ForEach(1...31, id: \.self) { d in Text("\(d)日").tag(d) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
                    
                    Button(action: onAdd) {
                        Label("追加", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .font(.title3.weight(.semibold))
                            .padding(10)
                            .background(Circle().fill(Color.accentColor.opacity(0.15)))
                    }
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardFill)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.06), radius: 12, y: 6)
            )
        }
        
        private var cardFill: some ShapeStyle {
            scheme == .dark ? Color.white.opacity(0.06) : .white
        }
    }
    
    private struct TemplateRowCard: View {
        @Binding var template: RecurringTodoTemplate
        let categories: [Category]
        let onDelete: () -> Void
        
        @Environment(\.colorScheme) private var scheme
        
        // 表示用ラベル
        private var dateLabel: String {
            template.dayOfMonth == 0 ? "月末" : "\(template.dayOfMonth)日"
        }
        private var categoryName: String {
            categories.first(where: { $0.id == template.defaultCategoryId })?.name ?? "未設定"
        }
        
        var body: some View {
            VStack(spacing: 4) {
                // ヘッダー行：トグル + タイトル + ゴミ箱
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Button {
                        template.isActive.toggle()
                    } label: {
                        Image(systemName: template.isActive ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(template.isActive ? Color.accentColor : .secondary)
                            .padding(.vertical, 3) // ベースライン微調整
                    }
                    .buttonStyle(.plain)
                    .alignmentGuide(.firstTextBaseline) { d in
                        d[VerticalAlignment.center] + 4   // ← 中心より2pt上をベースライン扱い
                    }
                    
                    TextField("タイトル", text: $template.title)
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash.fill").symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                }

                
                Divider().opacity(0.15)
                
                // セレクタ行：日付／カテゴリ／金額
                HStack {
                    // 日付
                    Menu {
                        Picker("日付", selection: $template.dayOfMonth) {
                            Text("月末").tag(0)
                            ForEach(1...31, id: \.self) { d in Text("\(d)日").tag(d) }
                        }
                    } label: {
                        Pill(text: dateLabel, systemImage: "calendar")
                    }
                    
                    // カテゴリ
                    Menu {
                        Picker("カテゴリ", selection: Binding(
                            get: { template.defaultCategoryId ?? categories.first?.id },
                            set: { template.defaultCategoryId = $0 }
                        )) {
                            ForEach(categories) { c in
                                Text(c.name).tag(Optional.some(c.id))
                            }
                        }
                    } label: {
                        Pill(text: categoryName, systemImage: "square.grid.2x2")
                    }
                    
                    // 金額
                    AmountPill(amountText: Binding(
                        get: { template.defaultAmount.map { numberStr($0) } ?? "" },
                        set: { template.defaultAmount = Int($0.filter(\.isNumber)) }
                    ))
                }
                
                // メモ
                TextField("メモ（任意）", text: Binding(
                    get: { template.defaultMemo ?? "" },
                    set: { template.defaultMemo = $0.isEmpty ? nil : $0 }
                ))
                .padding(.top, 1)
                .textInputAutocapitalization(.never)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : .white)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.06), radius: 10, y: 5)
            )
        }
        
        private var cardFill: some ShapeStyle {
            scheme == .dark ? Color.white.opacity(0.06) : .white
        }
        
        @ViewBuilder
        private func pillLabel(text: String, systemImage: String) -> some View {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundStyle(.secondary)
                Text(text).font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
        }
        
        private func numberStr(_ n: Int) -> String {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.groupingSeparator = ","
            return f.string(from: n as NSNumber) ?? "\(n)"
        }
    }
    
    /// 空状態のカード（上質インフォ）
    private struct EmptyStateCard: View {
        @Environment(\.colorScheme) private var scheme
        var body: some View {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "text.badge.plus")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                VStack(alignment: .leading, spacing: 4) {
                    Text("まだ登録がありません")
                        .font(.headline)
                    Text("上の「新規追加」から家賃や光熱費などを登録しましょう。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.06) : .white)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.06), radius: 12, y: 6)
            )
        }
    }
}

// MARK: - Mini subviews（軽く・再利用しやすく）

/// アイコン付きのシンプルPill
private struct Pill: View {
    let text: String
    let systemImage: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(text).font(.subheadline)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
    }
}

/// 金額入力用のPill（等幅数字＋薄い背景）
private struct AmountPill: View {
    @Binding var amountText: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "yensign.circle")
                .foregroundStyle(.secondary)
            TextField("金額", text: $amountText)
                .keyboardType(.numberPad)
                .frame(width: 110)
                .textInputAutocapitalization(.never)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.thinMaterial))
    }
}
