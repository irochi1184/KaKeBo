//
//  Services/DataStore+Backup.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/23.
//

import SwiftUI

extension DataStore {
    
    // ===== エクスポート（完全復元用 JSON） =====
    func exportFullBackupJSON(theme: AppTheme? = nil) -> Data {
        if transactions.isEmpty {
            let year = Calendar.current.component(.year, from: Date())
            return makeEmptyStateSampleBackupJSON(for: year)
        }

        // カテゴリ
        let cats: [BackupCategory] = categories.map {
            .init(id: $0.id, name: $0.name, symbolName: $0.symbolName, colorHex: colorToHex($0.color))
        }
        // 取引
        let txs: [BackupTransaction] = transactions.map {
            .init(id: $0.id, date: $0.date, amount: $0.amount,
                  typeRaw: $0.type == .income ? "income" : "expense",
                  memo: $0.memo, categoryId: $0.categoryId, tags: $0.tags)
        }
        // 毎月ToDo（あるなら）
        let recTodos: [BackupRecurringTodo]? = {
            let defaults = UserDefaults.appGroup
            guard let data = defaults.migratedData(forKey: "kakebo.recurring.templates"),
                  let arr  = try? JSONDecoder().decode([RecurringTodoTemplate].self, from: data)
            else { return nil }
            return arr.map {
                .init(id: $0.id, title: $0.title, dayOfMonth: $0.dayOfMonth, isActive: $0.isActive)
            }
        }()
        // 固定費
        let fixed: [BackupFixedExpense]? = {
            let defaults = UserDefaults.appGroup
            defaults.migrateIfNeeded(keys: [DataStore.fixedTemplatesKey])
            let data = defaults.migratedData(forKey: DataStore.fixedTemplatesKey) ?? Data()
            guard let arr = try? JSONDecoder().decode([FixedExpenseTemplate].self, from: data) else { return nil }
            return arr.map {
                .init(id: $0.id, title: $0.title, amount: $0.amount,
                      dayOfMonth: $0.dayOfMonth, categoryId: $0.categoryId,
                      memo: $0.memo ?? "", isActive: $0.isActive,
                      tags: $0.tags.isEmpty ? nil : $0.tags,
                      createdDate: $0.createdDate,
                      repeatMode: $0.repeatMode == .unlimited ? nil : $0.repeatMode,
                      appliedCount: $0.appliedCount > 0 ? $0.appliedCount : nil)
            }
        }()
        let frequent: [BackupFrequentTransaction]? = {
            guard !frequentTemplates.isEmpty else { return nil }
            return frequentTemplates.map {
                .init(
                    id: $0.id,
                    title: $0.title,
                    amount: $0.amount,
                    typeRaw: $0.type == .income ? "income" : "expense",
                    memo: $0.memo,
                    categoryId: $0.categoryId,
                    tags: $0.tags
                )
            }
        }()
//        // リマインダールール
//        let reminders: [BackupReminderRule]? = {
//            let data = UserDefaults.standard.data(forKey: ReminderStore.storageKey) ?? Data()
//            guard let arr = try? JSONDecoder().decode([ReminderRule].self, from: data) else { return nil }
//            return arr.map { .init(id: $0.id, enabled: $0.enabled, hour: $0.hour, minute: $0.minute) }
//        }()
        let dayNotes: [BackupDayNote]? = {
            let defaults = UserDefaults.appGroup
            guard let data = defaults.migratedData(forKey: "kakebo.daynotes.v1"),
                  let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
            return dict.map { BackupDayNote(dateKey: $0.key, text: $0.value) }
        }()

        let monthStart: BackupMonthStartSettings? = {
            let defaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
            guard let data = defaults.data(forKey: "kakebo.monthStart.settings"),
                  let settings = try? JSONDecoder().decode(MonthStartSettings.self, from: data) else { return nil }
            return BackupMonthStartSettings(
                isCustomStartEnabled: settings.isCustomStartEnabled,
                boundaryTypeRaw: settings.boundaryType.rawValue,
                startDay: settings.startDay,
                holidayAdjustmentRaw: settings.holidayAdjustment.rawValue
            )
        }()
        // テーマ
        let themeBackup: BackupTheme? = {
            guard let t = theme else { return nil }
            return .init(
                activePresetRaw: t.activePreset.rawValue,
                useSameAccentForBoth: t.useSameAccentForBoth,
                accentLightHex: colorToHex(t.accentLightRGBA.swiftUIColor),
                accentDarkHex:  colorToHex(t.accentDarkRGBA.swiftUIColor),
                useSameBackgroundForBoth: t.useSameBackgroundForBoth,
                backgroundLightHex: colorToHex(t.backgroundLightRGBA.swiftUIColor),
                backgroundDarkHex:  colorToHex(t.backgroundDarkRGBA.swiftUIColor),
                keypadIncomeHex: colorToHex(t.keypadIncomeRGBA.swiftUIColor),
                keypadExpenseHex: colorToHex(t.keypadExpenseRGBA.swiftUIColor),
                incomeHex: colorToHex(t.incomeRGBA.swiftUIColor),
                expenseHex: colorToHex(t.expenseRGBA.swiftUIColor),
                homeCardStyleRaw: t.homeCardStyle.rawValue,
                visualStyleRaw: t.visualStyle.rawValue,
                prefersCustomKeypad: t.prefersCustomKeypad
            )
        }()

        
        let payload = KaKeBoBackupV1(
            exportedAt: Date(),
            categories: cats,
            transactions: txs,
            recurringTodos: recTodos,
            fixedExpenses: fixed,
            frequentTransactions: frequent,
            //            reminders: reminders,
            dayNotes: dayNotes,
            monthStartSettings: monthStart,
            theme: themeBackup
        )
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? enc.encode(payload)) ?? Data()
    }
    
    // ===== インポート（JSON または 旧CSV） =====
    struct ImportReport { let inserted: Int; let createdCategories: Int; let skipped: Int }
    
    func importBackup(data: Data, applyTheme: ((AppTheme) -> Void)? = nil, applyMonthStartSettings: ((MonthStartSettings) -> Void)? = nil) throws -> ImportReport {

        // 1) まず JSON を試す
        if let rep = try? importJSONBackup(data: data, applyTheme: applyTheme, applyMonthStartSettings: applyMonthStartSettings) {
            return rep
        }
        // 2) ダメなら後方互換：旧 CSV を読む
        return try importCSV(data: data)
    }
    
    private func importJSONBackup(data: Data, applyTheme: ((AppTheme) -> Void)?, applyMonthStartSettings: ((MonthStartSettings) -> Void)?) throws -> ImportReport {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        let backup = try dec.decode(KaKeBoBackupV1.self, from: data)
        
        // 既存カテゴリを名前一致でマップ（同名は既存優先）
        var createdCats = 0
        var idMap: [UUID: UUID] = [:] // oldId -> newId
        
        for bc in backup.categories {
            if let existing = categories.first(where: { $0.name == bc.name }) {
                // 既存優先：見た目は既存を維持
                idMap[bc.id] = existing.id
            } else {
                let color = hexToColor(bc.colorHex) ?? DataStore.fallbackColor(for: bc.name)
                let new = Category(id: UUID(), name: bc.name, symbolName: bc.symbolName, color: color)
                addCategory(new)
                idMap[bc.id] = new.id
                createdCats += 1
            }
        }
        
        var inserted = 0
        var skipped = 0
        for bt in backup.transactions {
            guard let newCatId = idMap[bt.categoryId] else { skipped += 1; continue }
            // 既存重複回避（同一 ID または同一内容）簡易チェック
            if transactions.contains(where: { $0.id == bt.id }) {
                skipped += 1; continue
            }
            let type: TransactionType = (bt.typeRaw == "income") ? .income : .expense
            let tx = Transaction(id: UUID(), date: bt.date, amount: bt.amount, type: type, memo: bt.memo, categoryId: newCatId, tags: bt.tags ?? [])
            addTransaction(tx)
            inserted += 1
        }
        
        // 任意テーブル：復元できるものはする（無ければ無視）
        if let arr = backup.recurringTodos {
            let data = try JSONEncoder().encode(arr)
            let defaults = UserDefaults.appGroup
            defaults.migrateIfNeeded(keys: ["kakebo.recurring.templates"])
            defaults.set(data, forKey: "kakebo.recurring.templates")
        }
        if let arr = backup.fixedExpenses {
            let templates: [FixedExpenseTemplate] = arr.compactMap { tpl in
                guard let mappedCategory = tpl.categoryId.flatMap({ idMap[$0] }) else { return nil }
                return FixedExpenseTemplate(
                    id: tpl.id,
                    title: tpl.title,
                    amount: tpl.amount,
                    dayOfMonth: tpl.dayOfMonth,
                    categoryId: mappedCategory,
                    memo: tpl.memo,
                    isActive: tpl.isActive,
                    tags: tpl.tags ?? [],
                    createdDate: tpl.createdDate ?? Date(),
                    repeatMode: tpl.repeatMode ?? .unlimited,
                    appliedCount: tpl.appliedCount ?? 0
                )
            }
            let data = try JSONEncoder().encode(templates)
            let defaults = UserDefaults.appGroup
            defaults.migrateIfNeeded(keys: [DataStore.fixedTemplatesKey])
            defaults.set(data, forKey: DataStore.fixedTemplatesKey)
        }
        if let arr = backup.frequentTransactions {
            let templates: [FrequentTransactionTemplate] = arr.compactMap { tpl in
                guard let mappedCategory = idMap[tpl.categoryId] else { return nil }
                let type: TransactionType = (tpl.typeRaw == "income") ? .income : .expense
                return FrequentTransactionTemplate(
                    id: tpl.id,
                    title: tpl.title,
                    amount: tpl.amount,
                    type: type,
                    memo: tpl.memo,
                    categoryId: mappedCategory,
                    tags: tpl.tags
                )
            }
            replaceFrequentTemplatesForBackupImport(templates)
        }
//        if let arr = backup.reminders {
//            let data = try JSONEncoder().encode(arr)
//            UserDefaults.standard.set(data, forKey: ReminderStore.storageKey)
//        }
        if let notes = backup.dayNotes {
            let dict = Dictionary(uniqueKeysWithValues: notes.map { ($0.dateKey, $0.text) })
            let data = try JSONEncoder().encode(dict)
            let defaults = UserDefaults.appGroup
            defaults.migrateIfNeeded(keys: ["kakebo.daynotes.v1"])
            defaults.set(data, forKey: "kakebo.daynotes.v1")
            NotificationCenter.default.post(name: .dayNotesDidRestoreFromBackup, object: nil)
        }
        if let ms = backup.monthStartSettings {
            let settings = MonthStartSettings(
                isCustomStartEnabled: ms.isCustomStartEnabled,
                boundaryType: MonthBoundaryType(rawValue: ms.boundaryTypeRaw) ?? .startDay,
                startDay: ms.startDay,
                holidayAdjustment: MonthStartAdjustment(rawValue: ms.holidayAdjustmentRaw) ?? .none
            )
            let data = try JSONEncoder().encode(settings)
            let defaults = UserDefaults(suiteName: AppGroup.id) ?? .standard
            defaults.set(data, forKey: "kakebo.monthStart.settings")
            applyMonthStartSettings?(settings)
        }
        // --- import 側（applyThemeコールバックに渡して適用） ---
        if let th = backup.theme {
            var working = AppTheme()
            working.activePreset = AppTheme.Preset(rawValue: th.activePresetRaw) ?? .default
            working.useSameAccentForBoth = th.useSameAccentForBoth
            if let c = hexToColor(th.accentLightHex) { working.accentLightRGBA = .init(c) }
            if let c = hexToColor(th.accentDarkHex)  { working.accentDarkRGBA  = .init(c) }
            working.useSameBackgroundForBoth = th.useSameBackgroundForBoth
            if let c = hexToColor(th.backgroundLightHex) { working.backgroundLightRGBA = .init(c) }
            if let c = hexToColor(th.backgroundDarkHex)  { working.backgroundDarkRGBA  = .init(c) }
            // 電卓キーパッドカラー
            if let hex = th.keypadIncomeHex, let c = hexToColor(hex) { working.keypadIncomeRGBA = .init(c) }
            if let hex = th.keypadExpenseHex, let c = hexToColor(hex) { working.keypadExpenseRGBA = .init(c) }
            // 収支表示カラー
            if let hex = th.incomeHex, let c = hexToColor(hex) { working.incomeRGBA = .init(c) }
            if let hex = th.expenseHex, let c = hexToColor(hex) { working.expenseRGBA = .init(c) }
            // カードスタイル・ビジュアルスタイル
            if let raw = th.homeCardStyleRaw, let style = AppTheme.HomeCardStyle(rawValue: raw) { working.homeCardStyle = style }
            if let raw = th.visualStyleRaw, let style = AppTheme.VisualStyle(rawValue: raw) { working.visualStyle = style }
            // 電卓設定
            if let pref = th.prefersCustomKeypad { working.prefersCustomKeypad = pref }

            applyTheme?(working)
        }
        
        return .init(inserted: inserted, createdCategories: createdCats, skipped: skipped)
    }
    
    // ===== 旧 CSV の後方互換（“カテゴリ名のみ”前提） =====
    func importCSV(data: Data) throws -> ImportReport {
        guard let s = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "CSV", code: -1, userInfo: [NSLocalizedDescriptionKey:"文字コードがUTF-8ではありません"])
        }
        var lines = s.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.isEmpty == false else { return .init(inserted: 0, createdCategories: 0, skipped: 0) }
        let header = lines.removeFirst().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        func idx(_ name: String) -> Int? { header.firstIndex(of: name) }
        
        let iCat     = idx("category") ?? 2
        let iType    = idx("type") ?? 3
        let iAmount  = idx("amount") ?? 4
        let iMemo    = idx("memo") ?? 5
        let iDate    = idx("date") ?? 6
        let iSymbol  = idx("category_symbol")
        let iColorHex = idx("category_color_rgba")
        let iTags    = idx("tags") // ★ 任意の tags 列（例: "家族;同棲費用|個人用" など）
        
        var inserted = 0, createdCats = 0, skipped = 0
        
        for raw in lines {
            let cols = splitCSVRow(raw)
            guard cols.count > iDate else { skipped += 1; continue }
            let catName = stripQuotes(cols[iCat])
            
            // 既存 or 新規作成（色/アイコンあれば使う）
            let cat: Category = {
                if let ex = categories.first(where: { $0.name == catName }) { return ex }
                let sym = (iSymbol != nil && iSymbol! < cols.count) ? stripQuotes(cols[iSymbol!]) : "tag.fill"
                let hex = (iColorHex != nil && iColorHex! < cols.count) ? stripQuotes(cols[iColorHex!]) : nil
                let color = hex.flatMap(hexToColor) ?? DataStore.fallbackColor(for: catName)
                let c = Category(id: UUID(), name: catName, symbolName: sym, color: color)
                addCategory(c); createdCats += 1
                return c
            }()
            
            // 取引本体
            let type: TransactionType = (stripQuotes(cols[iType]) == "income") ? .income : .expense
            let amount = Int(stripQuotes(cols[iAmount])) ?? 0
            
            let df = DateFormatter(); df.locale = .init(identifier: "ja_JP"); df.dateFormat = "yyyy-MM-dd"
            let date = df.date(from: stripQuotes(cols[iDate])) ?? Date()
            
            let memo = iMemo < cols.count ? stripQuotes(cols[iMemo]) : ""
            
            // ★ tags 列を安全にパース（なければ []）
            let tags: [String] = {
                guard let iTags, iTags < cols.count else { return [] }
                let raw = stripQuotes(cols[iTags])
                return parseTags(raw)
            }()
            
            let tx = Transaction(
                id: UUID(),
                date: date,
                amount: amount,
                type: type,
                memo: memo,
                categoryId: cat.id,
                tags: tags
            )
            addTransaction(tx)
            inserted += 1
        }
        return .init(inserted: inserted, createdCategories: createdCats, skipped: skipped)
    }
    
    /// "家族;同棲費用|個人用 仕事用、貯蓄" のような自由区切り文字列を配列へ
    /// セミコロン/パイプ/日本語読点/空白で区切り、空要素は除去
    private func parseTags(_ raw: String) -> [String] {
        // まず全角・半角の空白を正規化
        let normalized = raw.replacingOccurrences(of: "　", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        // 想定区切り：; | 、（読点） スペース
        let separators = CharacterSet(charactersIn: ";|、 ")
        return normalized
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    
    // CSV の 1 行を安全に分割（ダブルクォート考慮の簡易版）
    private func splitCSVRow(_ row: String) -> [String] {
        var res: [String] = []
        var cur = ""
        var inQuotes = false
        for ch in row {
            if ch == "\"" {
                inQuotes.toggle()
                cur.append(ch)
            } else if ch == "," && !inQuotes {
                res.append(cur); cur = ""
            } else {
                cur.append(ch)
            }
        }
        res.append(cur)
        return res
    }
    private func stripQuotes(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\"") && t.hasSuffix("\"") && t.count >= 2 {
            t.removeFirst(); t.removeLast()
        }
        return t.replacingOccurrences(of: "\"\"", with: "\"")
    }
    
    // フォールバック色（名前ハッシュで安定）
    static func fallbackColor(for name: String) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .brown, .mint, .red]
        let idx = abs(name.hashValue) % palette.count
        return palette[idx]
    }
}
