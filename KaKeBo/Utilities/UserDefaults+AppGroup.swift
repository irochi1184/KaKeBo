import Foundation

extension UserDefaults {
    /// App Group 用の UserDefaults（未設定時は standard をフォールバック）
    static var appGroup: UserDefaults {
        UserDefaults(suiteName: AppGroup.id) ?? .standard
    }

    /// App Group にまだ値がない場合、legacy（デフォルト: standard）から移行する
    func migrateIfNeeded(from legacy: UserDefaults = .standard, keys: [String]) {
        guard self !== legacy else { return }
        for key in keys {
            guard object(forKey: key) == nil else { continue }
            if let legacyValue = legacy.object(forKey: key) {
                set(legacyValue, forKey: key)
            }
        }
    }

    /// legacy 側にのみ存在する Data を読み込んだ場合、そのまま移行して返す
    func migratedData(forKey key: String, legacy: UserDefaults = .standard) -> Data? {
        if let data = data(forKey: key) { return data }
        guard self !== legacy, let legacyData = legacy.data(forKey: key) else { return nil }
        set(legacyData, forKey: key)
        return legacyData
    }
}
