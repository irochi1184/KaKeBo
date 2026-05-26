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
        transactions.remove(atOffsets: offsets)
        saveTransactions()
        WidgetCenter.shared.reloadAllTimelines()
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
        transactions.removeAll(where: { $0.categoryId == cat.id })
        frequentTemplates.removeAll { $0.categoryId == cat.id }
        save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Persistence
    private func load() {
        categories = loadJSON([Category].self, from: categoriesURL) ?? []
        if let dtos = loadJSON([TransactionDTO].self, from: transactionsURL) {
            transactions = dtos.map { dto in
                let typeVal: TransactionType = (dto.type.lowercased() == "income") ? .income : .expense
                return Transaction(id: dto.id, date: dto.date, amount: dto.amount, type: typeVal, memo: dto.memo, categoryId: dto.categoryId, tags: dto.tags ?? [])
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
            return TransactionDTO(id: tx.id, date: tx.date, amount: tx.amount, type: typeStr, categoryId: tx.categoryId, memo: tx.memo, tags: tx.tags)
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
            return TransactionDTO(id: tx.id, date: tx.date, amount: tx.amount, type: typeStr, categoryId: tx.categoryId, memo: tx.memo, tags: tx.tags)
        }
        saveJSON(dtos, to: transactionsURL)
        WidgetCenter.shared.reloadAllTimelines()
        triggerAutoBackup()
    }
    private func saveBudgets() {
        saveJSON(budgets, to: budgetsURL)
        WidgetCenter.shared.reloadAllTimelines()
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
            transactions[i] = tx
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
        transactions.removeAll { ids.contains($0.id) }
        saveTransactions()
    }
    
    func deleteTransaction(id: UUID) {
        deleteTransactions(with: [id])
    }
    
    func updateTransaction(_ tx: Transaction) {
        // 既存更新だけに限定したい場合はこちらを使ってもOK
        guard let idx = transactions.firstIndex(where: { $0.id == tx.id }) else { return }
        transactions[idx] = tx
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
        transactions.removeAll { ids.contains($0.categoryId) }
        frequentTemplates.removeAll { ids.contains($0.categoryId) }
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
    
    /// 今月&今日までに“自動計上すべき”固定費を transactions に反映する
    /// - すでに当月分を計上済みのテンプレートはスキップ（Settings の手動計上からも共通利用可）
    func applyFixedExpensesForCurrentMonth() {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!   // 翌月初
        let today = cal.startOfDay(for: Date())
        
        // テンプレ取得
        let defaults = UserDefaults.appGroup
        defaults.migrateIfNeeded(keys: [Self.fixedTemplatesKey])
        var templates = (try? JSONDecoder().decode([FixedExpenseTemplate].self,
                                                   from: defaults.migratedData(forKey: Self.fixedTemplatesKey) ?? Data())) ?? []

        guard templates.contains(where: { $0.isActive }) else { return }
        
        // 当月の「計上済みテンプレID集合」を読み出し
        let monthKey = monthKeyString(for: start)  // "yyyy-MM"
        let postedKey = Self.fixedPostedKeyPrefix + monthKey
        defaults.migrateIfNeeded(keys: [postedKey])
        var posted: Set<UUID> = {
            if let data = defaults.migratedData(forKey: postedKey),
               let ids = try? JSONDecoder().decode([UUID].self, from: data) {
                return Set(ids)
            }
            return Set()
        }()
        
        var didAppend = false
        var templatesModified = false

        for (idx, t) in templates.enumerated() {
            guard t.isActive && !posted.contains(t.id) else { continue }
            // 繰り返し上限チェック
            guard !t.isRepeatLimitReached else {
                // 上限到達 → 自動で無効化
                templates[idx].isActive = false
                templatesModified = true
                continue
            }
            // 当月の”計上日”
            let due = computeDue(for: t, in: start)
            // 今日までに到来したものだけ自動計上（＝未来日はまだ）
            if due <= today && due >= start && due < end {
                // カテゴリがまだあるかチェック
                guard let _ = categories.first(where: { $0.id == t.categoryId }) else { continue }
                // 取引追加（支出）
                let tx = Transaction(
                    date: due,
                    amount: t.amount,
                    type: .expense,
                    memo: memoForFixedExpense(t),
                    categoryId: t.categoryId,
                    tags: t.tags
                )
                transactions.insert(tx, at: 0)
                posted.insert(t.id)
                templates[idx].appliedCount += 1
                templatesModified = true
                didAppend = true
            }
        }

        // テンプレートの更新を保存（appliedCount や isActive の変更）
        if templatesModified {
            defaults.set(try? JSONEncoder().encode(templates), forKey: Self.fixedTemplatesKey)
        }

        if didAppend {
            saveTransactions()
            // 計上済み更新
            let data = try? JSONEncoder().encode(Array(posted))
            defaults.set(data, forKey: postedKey)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
    
    /// 指定テンプレートを”今月”で即時計上（手動ボタン用）
    func postFixedExpenseNow(_ t: FixedExpenseTemplate) {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date()))!
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
    
    /// 31日対応（0=月末）
    private func computeDue(for tpl: FixedExpenseTemplate, in monthStart: Date) -> Date {
        let cal = Calendar.current
        if tpl.dayOfMonth == 0 {
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart)!
            return cal.startOfDay(for: end)
        } else {
            let range = cal.range(of: .day, in: .month, for: monthStart)!
            let day = min(tpl.dayOfMonth, range.count)
            return cal.startOfDay(for:
                                    cal.date(from: DateComponents(year: cal.component(.year, from: monthStart),
                                                                  month: cal.component(.month, from: monthStart),
                                                                  day: day)) ?? monthStart
            )
        }
    }
    
    private func monthKeyString(for monthStart: Date) -> String {
        let f = DateFormatter(); f.locale = .init(identifier: "ja_JP"); f.dateFormat = "yyyy-MM"
        return f.string(from: monthStart)
    }
}
