import Foundation
import SwiftUI
import Combine
import WidgetKit

final class DataStore: ObservableObject {
    @Published private(set) var categories: [Category] = []
    @Published private(set) var transactions: [Transaction] = []
    @Published private(set) var budgets: [Budget] = []
    @Published private(set) var frequentTemplates: [FrequentTransactionTemplate] = []

    private let categoriesURL: URL
    private let transactionsURL: URL
    private let budgetsURL: URL

    init() {
        guard let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id) else {
#if DEBUG
            print("❌ AppGroup URL 取得に失敗: \(AppGroup.id)。entitlements/Team/BundleID を確認して下さい。")
#endif
            // フォールバック：ドキュメント配下（初期起動用・暫定）
            let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            categoriesURL   = doc.appendingPathComponent("categories.json")
            transactionsURL = doc.appendingPathComponent("transactions.json")
            budgetsURL      = doc.appendingPathComponent("budgets.json")
            load()
            if categories.isEmpty { seed() }
            loadFrequentTemplates()
            return
        }
        
        categoriesURL   = base.appendingPathComponent("categories.json")
        transactionsURL = base.appendingPathComponent("transactions.json")
        budgetsURL      = base.appendingPathComponent("budgets.json")
        
        // 旧ドキュメントからの一度きりの移行（既存ユーザー救済）
        migrateFromDocumentsIfNeeded(to: base)

        // v2.3.1 で誤った AppGroup コンテナに書き込まれたデータの復旧
        recoverFromWrongAppGroup(correctBase: base)

        load()
        if categories.isEmpty { seed() }
        loadFrequentTemplates()

        // 起動時に、どの取引からも参照されていない写真ファイル（追加途中でキャンセルされた等）を掃除
        let referenced = Set(transactions.flatMap { $0.photoFilenames ?? [] })
        PhotoStore.shared.purgeOrphans(keeping: referenced)
    }

    /// v2.3.1 で誤って使用された AppGroup コンテナからデータを復旧
    private func recoverFromWrongAppGroup(correctBase: URL) {
        let recoveredKey = "kakebo.v231.recovery.done"
        let defaults = UserDefaults.appGroup
        if defaults.bool(forKey: recoveredKey) { return }

        // 誤った AppGroup ID（v2.3.1 で一時的に使用されたもの）
        let wrongGroupId = "group.com.irochi.KaKeBo"
        guard let wrongBase = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: wrongGroupId) else {
            defaults.set(true, forKey: recoveredKey)
            return
        }

        let fm = FileManager.default
        let txCorrect = correctBase.appendingPathComponent("transactions.json")
        let txWrong = wrongBase.appendingPathComponent("transactions.json")

        // 誤ったコンテナに取引データがなければ復旧不要
        guard fm.fileExists(atPath: txWrong.path),
              let wrongData = try? Data(contentsOf: txWrong),
              wrongData.count > 10 else {
            defaults.set(true, forKey: recoveredKey)
            return
        }

        // 誤ったコンテナのほうが取引データが大きい（＝実データがある）場合に復旧
        let correctSize = (try? fm.attributesOfItem(atPath: txCorrect.path)[.size] as? Int) ?? 0
        let wrongSize = (try? fm.attributesOfItem(atPath: txWrong.path)[.size] as? Int) ?? 0

        if wrongSize > correctSize {
            let files = ["categories.json", "transactions.json", "budgets.json"]
            for name in files {
                let src = wrongBase.appendingPathComponent(name)
                let dest = correctBase.appendingPathComponent(name)
                guard fm.fileExists(atPath: src.path) else { continue }
                do {
                    if fm.fileExists(atPath: dest.path) {
                        try fm.removeItem(at: dest)
                    }
                    try fm.copyItem(at: src, to: dest)
#if DEBUG
                    print("✅ Recovered \(name) from wrong AppGroup container.")
#endif
                } catch { print("Recovery error(\(name)):", error) }
            }
        }

        defaults.set(true, forKey: recoveredKey)
    }

    private func migrateFromDocumentsIfNeeded(to appGroupBase: URL) {
        let doc = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let old = [
            ("categories.json", categoriesURL),
            ("transactions.json", transactionsURL),
            ("budgets.json", budgetsURL)
        ]
        for (name, dest) in old {
            let src = doc.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: src.path),
               !FileManager.default.fileExists(atPath: dest.path) {
                do {
                    try FileManager.default.copyItem(at: src, to: dest)
#if DEBUG
                    print("Migrated \(name) to AppGroup container.")
#endif
                } catch { print("Migration error(\(name)):", error) }
            }
        }
    }

    private func seed() {
        let presetsByName = Dictionary(uniqueKeysWithValues: PresetCategory.all.map { ($0.name, $0) })
        
        categories = [
            "食費", "日用品費", "水道光熱費", "交通費", "通信料", "住宅費", "医療費",
            "交際費", "娯楽費", "給与", "その他収入"
        ].map { name in
            if let preset = presetsByName[name] {
                return Category(name: preset.name, symbolName: preset.symbol, color: preset.color)
            } else {
                return Category(name: name, symbolName: "tag.fill", color: .gray)
            }
        }
        save()
    }


    // MARK: - CRUD
    func addTransaction(_ tx: Transaction) {
        transactions.insert(tx, at: 0)
        saveTransactions()
        ReviewRequestManager.shared.recordSuccessfulSave()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func deleteTransactions(at offsets: IndexSet) {
        let removed = offsets.map { transactions[$0] }
        transactions.remove(atOffsets: offsets)
        cleanupPhotos(for: removed)
        saveTransactions()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// 取引から外れた写真の実体ファイルを削除する（孤児ファイル防止）。
    private func cleanupPhotos(for removed: [Transaction]) {
        let names = removed.flatMap { $0.photoFilenames ?? [] }
        if !names.isEmpty { PhotoStore.shared.delete(names) }
    }

    func addCategory(_ cat: Category) {
        categories.append(cat)
        saveCategories()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func updateCategory(_ cat: Category) {
        if let idx = categories.firstIndex(where: { $0.id == cat.id }) {
            categories[idx] = cat
            saveCategories()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    func deleteCategory(_ cat: Category) {
        categories.removeAll(where: { $0.id == cat.id })
        let removedTx = transactions.filter { $0.categoryId == cat.id }
        transactions.removeAll(where: { $0.categoryId == cat.id })
        frequentTemplates.removeAll { $0.categoryId == cat.id }
        cleanupPhotos(for: removedTx)
        save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Persistence
    private func load() {
        categories = loadJSON([Category].self, from: categoriesURL) ?? []
        if let dtos = loadJSON([TransactionDTO].self, from: transactionsURL) {
            transactions = dtos.map { dto in
                let typeVal: TransactionType = (dto.type.lowercased() == "income") ? .income : .expense
                return Transaction(id: dto.id, date: dto.date, amount: dto.amount, type: typeVal, memo: dto.memo, categoryId: dto.categoryId, tags: dto.tags ?? [], photoFilenames: dto.photoFilenames)
            }
        } else if let old = loadJSON([Transaction].self, from: transactionsURL) {
            transactions = old
        } else {
            transactions = []
        }
        budgets = loadJSON([Budget].self, from: budgetsURL) ?? []
    }

    private func loadFrequentTemplates() {
        let defaults = UserDefaults.appGroup
        let data = defaults.migratedData(forKey: Self.frequentTemplatesKey) ?? Data()
        let decoded = (try? JSONDecoder().decode([FrequentTransactionTemplate].self, from: data)) ?? []

        // 削除されたカテゴリを除外してから反映
        let validCategoryIds = Set(categories.map { $0.id })
        frequentTemplates = decoded.filter { validCategoryIds.contains($0.categoryId) }
    }

    public func save() {
        saveJSON(categories, to: categoriesURL)

        let dtos: [TransactionDTO] = transactions.map { tx in
            let typeStr: String
            switch tx.type { case .income: typeStr = "income"; case .expense: typeStr = "expense" }
            return TransactionDTO(id: tx.id, date: tx.date, amount: tx.amount, type: typeStr, categoryId: tx.categoryId, memo: tx.memo, tags: tx.tags, photoFilenames: tx.photoFilenames)
        }
        saveJSON(dtos, to: transactionsURL)

        saveJSON(budgets, to: budgetsURL)
        WidgetCenter.shared.reloadAllTimelines()
        triggerAutoBackup()
        PhoneSessionManager.shared.pushUpdate()
    }

    private func saveCategories() {
        saveJSON(categories, to: categoriesURL)
        WidgetCenter.shared.reloadAllTimelines()
        triggerAutoBackup()
    }
    private func saveTransactions() {
        let dtos: [TransactionDTO] = transactions.map { tx in
            let typeStr: String
            switch tx.type { case .income: typeStr = "income"; case .expense: typeStr = "expense" }
            return TransactionDTO(id: tx.id, date: tx.date, amount: tx.amount, type: typeStr, categoryId: tx.categoryId, memo: tx.memo, tags: tx.tags, photoFilenames: tx.photoFilenames)
        }
        saveJSON(dtos, to: transactionsURL)
        WidgetCenter.shared.reloadAllTimelines()
        triggerAutoBackup()
    }
    private func saveBudgets() {
        saveJSON(budgets, to: budgetsURL)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - 予算 CRUD

    /// 指定月・カテゴリの予算を設定（0以下なら削除）
    func setBudget(monthId: String, categoryId: UUID, limitAmount: Int) {
        if limitAmount <= 0 {
            budgets.removeAll { $0.monthId == monthId && $0.categoryId == categoryId }
        } else if let idx = budgets.firstIndex(where: { $0.monthId == monthId && $0.categoryId == categoryId }) {
            budgets[idx].limitAmount = limitAmount
        } else {
            budgets.append(Budget(monthId: monthId, categoryId: categoryId, limitAmount: limitAmount))
        }
        saveBudgets()
    }

    /// カテゴリ別の金額をまとめて指定月の予算として設定する
    /// （先月の支出をまるまる予算にする等の一括反映に使用。金額0以下のカテゴリはスキップ）
    func applyExpensesAsBudgets(monthId: String, expenseByCategory: [UUID: Int]) {
        for (categoryId, amount) in expenseByCategory where amount > 0 {
            if let idx = budgets.firstIndex(where: { $0.monthId == monthId && $0.categoryId == categoryId }) {
                budgets[idx].limitAmount = amount
                budgets[idx].isEnabled = true
            } else {
                budgets.append(Budget(monthId: monthId, categoryId: categoryId, limitAmount: amount))
            }
        }
        saveBudgets()
    }

    /// カテゴリ予算の有効/無効を切り替える（金額は保持したまま一時停止）
    func setBudgetEnabled(monthId: String, categoryId: UUID, isEnabled: Bool) {
        guard let idx = budgets.firstIndex(where: { $0.monthId == monthId && $0.categoryId == categoryId }) else { return }
        budgets[idx].isEnabled = isEnabled
        saveBudgets()
    }

    /// 指定月の全予算を前月からコピー
    func copyBudgetsFromPreviousMonth(to monthId: String, from previousMonthId: String) {
        let existing = Set(budgets.filter { $0.monthId == monthId }.map { $0.categoryId })
        let source = budgets.filter { $0.monthId == previousMonthId }
        for b in source where !existing.contains(b.categoryId) {
            budgets.append(Budget(monthId: monthId, categoryId: b.categoryId, limitAmount: b.limitAmount, isEnabled: b.isEnabled))
        }
        saveBudgets()
    }

    /// 指定月の予算合計（有効な予算のみ）
    func totalBudget(for monthId: String) -> Int {
        budgets.filter { $0.monthId == monthId && $0.isEnabled }.reduce(0) { $0 + $1.limitAmount }
    }

    private func triggerAutoBackup() {
        AutoBackupManager.shared.performIfNeeded(
            categories: categories,
            transactions: transactions,
            budgets: budgets,
            frequentTemplates: frequentTemplates
        )
    }

    /// 自動バックアップからの完全復元
    func restoreFromAutoBackup(payload: AutoBackupPayload) {
        self.categories = payload.categories
        self.transactions = payload.transactions
        self.budgets = payload.budgets

        // UserDefaults データの復元
        let defaults = UserDefaults.appGroup

        if let fixed = payload.fixedExpenses {
            let data = try? JSONEncoder().encode(fixed)
            defaults.set(data, forKey: DataStore.fixedTemplatesKey)
        }
        if let templates = payload.frequentTemplates {
            replaceFrequentTemplatesForBackupImport(templates)
        }
        if let todos = payload.recurringTodos {
            let data = try? JSONEncoder().encode(todos)
            defaults.set(data, forKey: "kakebo.recurring.templates")
        }
        if let notes = payload.dayNotes {
            let data = try? JSONEncoder().encode(notes)
            defaults.set(data, forKey: "kakebo.daynotes.v1")
            NotificationCenter.default.post(name: .dayNotesDidRestoreFromBackup, object: nil)
        }
        if let ms = payload.monthStartSettings {
            let data = try? JSONEncoder().encode(ms)
            let ud = UserDefaults(suiteName: AppGroup.id) ?? .standard
            ud.set(data, forKey: "kakebo.monthStart.settings")
        }
        if let theme = payload.theme {
            let data = try? JSONEncoder().encode(theme)
            let ud = UserDefaults(suiteName: AppGroup.id) ?? .standard
            ud.set(data, forKey: "kakebo.theme.data")
        }
        save()
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        // Try ISO8601 first
        let dec1 = JSONDecoder()
        dec1.dateDecodingStrategy = .iso8601
        if let val = try? dec1.decode(T.self, from: data) { return val }
        // Fallback to default decoding
        let dec2 = JSONDecoder()
        if let val = try? dec2.decode(T.self, from: data) { return val }
#if DEBUG
        print("⚠️ loadJSON decode failed for: \(url.lastPathComponent)")
#endif
        return nil
    }

    private func saveJSON<T: Encodable>(_ value: T, to url: URL) {
        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            let data = try enc.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Save error (\(url.lastPathComponent)):", error)
        }
    }
}

extension DataStore {
    func upsertTransaction(_ tx: Transaction) {
        let shouldCountAsNewSave = !transactions.contains(where: { $0.id == tx.id })
        if let i = transactions.firstIndex(where: { $0.id == tx.id }) {
            // 編集で外された写真の実体を削除（孤児ファイル防止）
            let oldNames = Set(transactions[i].photoFilenames ?? [])
            let newNames = Set(tx.photoFilenames ?? [])
            let orphaned = oldNames.subtracting(newNames)
            transactions[i] = tx
            if !orphaned.isEmpty { PhotoStore.shared.delete(Array(orphaned)) }
        } else {
            transactions.insert(tx, at: 0)
        }
        saveTransactions()
        if shouldCountAsNewSave {
            ReviewRequestManager.shared.recordSuccessfulSave()
        }
    }
    
    /// ID配列でまとめて削除して保存
    func deleteTransactions(with ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let removed = transactions.filter { ids.contains($0.id) }
        transactions.removeAll { ids.contains($0.id) }
        cleanupPhotos(for: removed)
        saveTransactions()
    }
    
    func deleteTransaction(id: UUID) {
        deleteTransactions(with: [id])
    }
    
    func updateTransaction(_ tx: Transaction) {
        // 既存更新だけに限定したい場合はこちらを使ってもOK
        guard let idx = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        // 編集で外された写真の実体を削除（孤児ファイル防止）
        let oldNames = Set(transactions[idx].photoFilenames ?? [])
        let newNames = Set(tx.photoFilenames ?? [])
        let orphaned = oldNames.subtracting(newNames)
        transactions[idx] = tx
        if !orphaned.isEmpty { PhotoStore.shared.delete(Array(orphaned)) }
        saveTransactions()
    }
    
    func moveCategories(from offsets: IndexSet, to destination: Int) {
        categories.move(fromOffsets: offsets, toOffset: destination)
        saveCategories()
    }
    
    /// 複数IDまとめて削除（カテゴリ＆紐づく取引）
    func deleteCategories(with ids: [UUID]) {
        guard !ids.isEmpty else { return }
        categories.removeAll { ids.contains($0.id) }
        let removedTx = transactions.filter { ids.contains($0.categoryId) }
        transactions.removeAll { ids.contains($0.categoryId) }
        frequentTemplates.removeAll { ids.contains($0.categoryId) }
        cleanupPhotos(for: removedTx)
        save()
    }

    /// 未分類カテゴリを表す固定UUID（どのカテゴリにも一致しないため「未分類」として表示される）
    static let uncategorizedID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    /// カテゴリを削除し、紐づく取引は未分類（固定ID）に移動
    func deleteCategoriesMovingTransactions(with ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for i in transactions.indices where ids.contains(transactions[i].categoryId) {
            transactions[i].categoryId = Self.uncategorizedID
        }
        categories.removeAll { ids.contains($0.id) }
        frequentTemplates.removeAll { ids.contains($0.categoryId) }
        save()
    }

    /// 指定カテゴリIDに紐づく取引の件数を返す
    func transactionCount(for categoryIDs: [UUID]) -> Int {
        transactions.filter { categoryIDs.contains($0.categoryId) }.count
    }
    
    /// 固定費テンプレートの保存領域（SettingsView でも使う）
    static let fixedTemplatesKey = "kakebo.fixed.templates"
    static let fixedPostedKeyPrefix = "kakebo.fixed.posted." // + "yyyy-MM" に対して Set<UUID> を保持
    static let frequentTemplatesKey = "kakebo.frequent.transactions"

    // MARK: - よく使う取引テンプレート
    func addFrequentTemplate(_ tpl: FrequentTransactionTemplate) {
        // 同じカテゴリ・金額・メモ・種別のものは置き換え
        if let idx = frequentTemplates.firstIndex(where: { $0.isEquivalent(to: tpl) }) {
            frequentTemplates[idx] = tpl
        } else {
            frequentTemplates.insert(tpl, at: 0)
        }
        saveFrequentTemplates()
    }

    func deleteFrequentTemplate(id: UUID) {
        frequentTemplates.removeAll { $0.id == id }
        saveFrequentTemplates()
    }

    private func saveFrequentTemplates() {
        let defaults = UserDefaults.appGroup
        defaults.set(try? JSONEncoder().encode(frequentTemplates), forKey: Self.frequentTemplatesKey)
    }

    func moveFrequentTemplates(from offsets: IndexSet, to destination: Int) {
        frequentTemplates.move(fromOffsets: offsets, toOffset: destination)
        saveFrequentTemplates()
    }

    /// バックアップ復元用：テンプレート一覧を丸ごと差し替えて保存
    func replaceFrequentTemplatesForBackupImport(_ templates: [FrequentTransactionTemplate]) {
        frequentTemplates = templates
        saveFrequentTemplates()
    }
    
    /// 今日までに“自動計上すべき”固定費を transactions に反映する
    /// - 支払日の休日補正で月をまたぐ可能性があるため、前月・当月・翌月を対象月として確認する
    /// - 計上済み管理は「実際の取引日」ではなく「固定費の対象月」単位で保持する
    func applyFixedExpensesForCurrentMonth(referenceDate: Date = Date()) {
        let cal = Calendar.current
        guard let currentMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: referenceDate)) else {
            return
        }
        let today = cal.startOfDay(for: referenceDate)

        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: [Self.fixedTemplatesKey])
        var templates = (try? JSONDecoder().decode(
            [FixedExpenseTemplate].self,
            from: defaults.migratedData(forKey: Self.fixedTemplatesKey) ?? Data()
        )) ?? []

        guard templates.contains(where: { $0.isActive }) else { return }

        // 月初の前倒し・月末の後ろ倒しを拾うため、対象月を前後1か月まで確認する
        let targetMonthStarts = [-1, 0, 1].compactMap {
            cal.date(byAdding: .month, value: $0, to: currentMonthStart)
        }

        var didAppend = false
        var templatesModified = false

        for targetMonthStart in targetMonthStarts {
            let monthKey = monthKeyString(for: targetMonthStart)
            let postedKey = Self.fixedPostedKeyPrefix + monthKey
            defaults.migrateIfNeeded(keys: [postedKey])

            var posted: Set<UUID> = {
                if let data = defaults.migratedData(forKey: postedKey),
                   let ids = try? JSONDecoder().decode([UUID].self, from: data) {
                    return Set(ids)
                }
                return Set()
            }()

            var postedModified = false

            for idx in templates.indices {
                let template = templates[idx]
                guard template.isActive && !posted.contains(template.id) else { continue }

                // 繰り返し上限チェック
                guard !template.isRepeatLimitReached else {
                    templates[idx].isActive = false
                    templatesModified = true
                    continue
                }

                let due = computeDue(for: template, in: targetMonthStart)

                // 対象月の支払日を休日補正した結果が今日までに到来していれば計上する
                guard due <= today else { continue }

                // カテゴリがまだあるかチェック
                guard categories.contains(where: { $0.id == template.categoryId }) else { continue }

                let tx = Transaction(
                    date: due,
                    amount: template.amount,
                    type: .expense,
                    memo: memoForFixedExpense(template),
                    categoryId: template.categoryId,
                    tags: template.tags
                )
                transactions.insert(tx, at: 0)

                posted.insert(template.id)
                postedModified = true
                templates[idx].appliedCount += 1
                templatesModified = true
                didAppend = true
            }

            if postedModified {
                let data = try? JSONEncoder().encode(Array(posted))
                defaults.set(data, forKey: postedKey)
            }
        }

        if templatesModified {
            defaults.set(try? JSONEncoder().encode(templates), forKey: Self.fixedTemplatesKey)
        }

        if didAppend {
            saveTransactions()
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// 指定テンプレートを”今月”で即時計上（手動ボタン用）
    func postFixedExpenseNow(_ t: FixedExpenseTemplate) {
        let cal = Calendar.current
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) else { return }
        let due = computeDue(for: t, in: start)

        guard let _ = categories.first(where: { $0.id == t.categoryId }) else { return }
        let tx = Transaction(
            date: due,
            amount: t.amount,
            type: .expense,
            memo: memoForFixedExpense(t),
            categoryId: t.categoryId,
            tags: t.tags
        )
        transactions.insert(tx, at: 0)
        saveTransactions()

        // 当月の posted 印も付ける
        let defaults = UserDefaults.appGroup
        let monthKey = monthKeyString(for: start)
        let postedKey = Self.fixedPostedKeyPrefix + monthKey
        defaults.migrateIfNeeded(keys: [postedKey])
        var posted: Set<UUID> = {
            if let data = defaults.migratedData(forKey: postedKey),
               let ids = try? JSONDecoder().decode([UUID].self, from: data) {
                return Set(ids)
            }
            return Set()
        }()
        posted.insert(t.id)
        let data = try? JSONEncoder().encode(Array(posted))
        defaults.set(data, forKey: postedKey)

        // appliedCount を更新
        defaults.migrateIfNeeded(keys: [Self.fixedTemplatesKey])
        if let tplData = defaults.migratedData(forKey: Self.fixedTemplatesKey),
           var templates = try? JSONDecoder().decode([FixedExpenseTemplate].self, from: tplData),
           let idx = templates.firstIndex(where: { $0.id == t.id }) {
            templates[idx].appliedCount += 1
            defaults.set(try? JSONEncoder().encode(templates), forKey: Self.fixedTemplatesKey)
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func memoForFixedExpense(_ tpl: FixedExpenseTemplate) -> String {
        let title = tpl.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let memo = tpl.memo?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let memo, !memo.isEmpty {
            let parts = [title, memo].filter { !$0.isEmpty }
            return parts.joined(separator: " / ")
        }
        return title
    }
    
    /// 31日対応（0=月末）＋土日祝の支払日補正
    private func computeDue(for tpl: FixedExpenseTemplate, in monthStart: Date) -> Date {
        let cal = Calendar.current

        let baseDue: Date = {
            if tpl.dayOfMonth == 0 {
                guard let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) else {
                    return monthStart
                }
                return cal.startOfDay(for: end)
            }

            guard let range = cal.range(of: .day, in: .month, for: monthStart) else {
                return monthStart
            }
            let day = min(tpl.dayOfMonth, range.count)
            let components = DateComponents(
                year: cal.component(.year, from: monthStart),
                month: cal.component(.month, from: monthStart),
                day: day
            )
            return cal.startOfDay(for: cal.date(from: components) ?? monthStart)
        }()

        switch tpl.paymentDateAdjustment {
        case .none:
            return baseDue
        case .previousBusinessDay:
            return adjustedBusinessDay(from: baseDue, direction: -1, calendar: cal)
        case .nextBusinessDay:
            return adjustedBusinessDay(from: baseDue, direction: 1, calendar: cal)
        }
    }

    private func adjustedBusinessDay(from date: Date, direction: Int, calendar: Calendar) -> Date {
        guard direction == -1 || direction == 1 else {
            return calendar.startOfDay(for: date)
        }

        var candidate = calendar.startOfDay(for: date)
        while !isBusinessDay(candidate, calendar: calendar) {
            guard let moved = calendar.date(byAdding: .day, value: direction, to: candidate) else {
                return candidate
            }
            candidate = calendar.startOfDay(for: moved)
        }
        return candidate
    }

    private func isBusinessDay(_ date: Date, calendar: Calendar) -> Bool {
        !calendar.isDateInWeekend(date) && !JapaneseHolidayCalendar.isHoliday(date, calendar: calendar)
    }

    private func monthKeyString(for monthStart: Date) -> String {
        let f = DateFormatter(); f.locale = .init(identifier: "ja_JP"); f.dateFormat = "yyyy-MM"
        return f.string(from: monthStart)
    }
}


// MARK: - 日本の祝日判定

/// 固定費の支払日補正に使う日本の祝日判定。
/// KaKeBo の運用期間を考慮し、2007年以降の祝日制度を対象とする。
private enum JapaneseHolidayCalendar {
    static func isHoliday(_ date: Date, calendar sourceCalendar: Calendar = .current) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "ja_JP")
        calendar.timeZone = sourceCalendar.timeZone

        let normalized = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: normalized)
        guard year >= 2007 else { return false }

        return holidays(in: year, calendar: calendar).contains(normalized)
    }

    private static func holidays(in year: Int, calendar: Calendar) -> Set<Date> {
        var nationalHolidays = Set<Date>()

        func add(_ month: Int, _ day: Int) {
            if let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) {
                nationalHolidays.insert(calendar.startOfDay(for: date))
            }
        }

        func addNthMonday(month: Int, ordinal: Int) {
            guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return }
            let firstWeekday = calendar.component(.weekday, from: first)
            let monday = 2
            let offset = (monday - firstWeekday + 7) % 7
            let day = 1 + offset + (ordinal - 1) * 7
            add(month, day)
        }

        // 毎年の祝日
        add(1, 1)                 // 元日
        addNthMonday(month: 1, ordinal: 2) // 成人の日
        add(2, 11)                // 建国記念の日

        if year <= 2018 {
            add(12, 23)           // 天皇誕生日（平成）
        } else if year >= 2020 {
            add(2, 23)            // 天皇誕生日（令和）
        }

        add(3, vernalEquinoxDay(year: year))
        add(4, 29)                // 昭和の日
        add(5, 3)                 // 憲法記念日
        add(5, 4)                 // みどりの日
        add(5, 5)                 // こどもの日

        // 海の日・スポーツの日・山の日は東京五輪による特例を考慮
        switch year {
        case 2020:
            add(7, 23)            // 海の日
            add(7, 24)            // スポーツの日
            add(8, 10)            // 山の日
        case 2021:
            add(7, 22)            // 海の日
            add(7, 23)            // スポーツの日
            add(8, 8)             // 山の日（振替休日は後段で算出）
        default:
            addNthMonday(month: 7, ordinal: 3) // 海の日
            add(8, 11)            // 山の日
            addNthMonday(month: 10, ordinal: 2) // スポーツの日
        }

        addNthMonday(month: 9, ordinal: 3) // 敬老の日
        add(9, autumnEquinoxDay(year: year))
        add(11, 3)                // 文化の日
        add(11, 23)               // 勤労感謝の日

        // 2019年の即位関連の祝日
        if year == 2019 {
            add(5, 1)
            add(10, 22)
        }

        var holidays = nationalHolidays

        // 国民の休日：前後を国民の祝日に挟まれた平日
        if let yearStart = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
           let nextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)),
           let days = calendar.dateComponents([.day], from: yearStart, to: nextYear).day {
            for offset in 1..<(max(days - 1, 1)) {
                guard let date = calendar.date(byAdding: .day, value: offset, to: yearStart),
                      let previous = calendar.date(byAdding: .day, value: -1, to: date),
                      let next = calendar.date(byAdding: .day, value: 1, to: date) else {
                    continue
                }

                let normalized = calendar.startOfDay(for: date)
                let weekday = calendar.component(.weekday, from: normalized)
                guard weekday != 1 && weekday != 7 else { continue }

                if nationalHolidays.contains(calendar.startOfDay(for: previous))
                    && nationalHolidays.contains(calendar.startOfDay(for: next)) {
                    holidays.insert(normalized)
                }
            }
        }

        // 振替休日：日曜の国民の祝日の直後にある最初の休日でない日
        for holiday in nationalHolidays where calendar.component(.weekday, from: holiday) == 1 {
            guard var substitute = calendar.date(byAdding: .day, value: 1, to: holiday) else { continue }
            substitute = calendar.startOfDay(for: substitute)

            while holidays.contains(substitute) {
                guard let next = calendar.date(byAdding: .day, value: 1, to: substitute) else { break }
                substitute = calendar.startOfDay(for: next)
            }
            holidays.insert(substitute)
        }

        return holidays
    }

    private static func vernalEquinoxDay(year: Int) -> Int {
        // 1980〜2099年で使える近似式
        Int(20.8431 + 0.242194 * Double(year - 1980) - Double((year - 1980) / 4))
    }

    private static func autumnEquinoxDay(year: Int) -> Int {
        // 1980〜2099年で使える近似式
        Int(23.2488 + 0.242194 * Double(year - 1980) - Double((year - 1980) / 4))
    }
}
