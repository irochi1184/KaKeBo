import Foundation

struct EmailImportSettings: Codable, Equatable {
    static let storageKey = "kakebo.email.import.settings"

    var rakutenPaySender: String
    var jcbSender: String
    var rakutenPayCategoryId: UUID?
    var jcbCategoryId: UUID?

    static func load(from defaults: UserDefaults = .appGroup) -> EmailImportSettings {
        defaults.migrateIfNeeded(keys: [storageKey])
        guard let data = defaults.migratedData(forKey: storageKey),
              let settings = try? JSONDecoder().decode(EmailImportSettings.self, from: data) else {
            return EmailImportSettings(
                rakutenPaySender: "",
                jcbSender: "",
                rakutenPayCategoryId: nil,
                jcbCategoryId: nil
            )
        }
        return settings
    }

    func save(to defaults: UserDefaults = .appGroup) {
        let data = try? JSONEncoder().encode(self)
        defaults.set(data, forKey: Self.storageKey)
    }
}
