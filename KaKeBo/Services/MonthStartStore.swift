//
//  Services/MonthStartStore.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/12/08.
//

import Foundation
import Combine

final class MonthStartStore: ObservableObject {
    @Published var settings: MonthStartSettings {
        didSet { persist() }
    }

    private static let storageKey = "kakebo.monthStart.settings"
    private let userDefaults: UserDefaults
    private let holidayProvider = JapaneseHolidayProvider()

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: AppGroup.id)) {
        self.userDefaults = userDefaults ?? .standard

        if let saved = Self.load(from: self.userDefaults) {
            settings = saved
        } else if let migrated = Self.migrateFromLegacySuites(to: self.userDefaults) {
            settings = migrated
        } else {
            settings = .default
            persist()
        }
    }

    func resolver(calendar: Calendar = .current) -> MonthStartResolver {
        MonthStartResolver(settings: settings, calendar: calendar, holidayProvider: holidayProvider)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            userDefaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> MonthStartSettings? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(MonthStartSettings.self, from: data)
    }

    private static func migrateFromLegacySuites(to target: UserDefaults) -> MonthStartSettings? {
        for legacyId in AppGroup.legacyIds {
            guard let legacyDefaults = UserDefaults(suiteName: legacyId),
                  let data = legacyDefaults.data(forKey: storageKey) else { continue }

            target.set(data, forKey: storageKey)
            if let settings = try? JSONDecoder().decode(MonthStartSettings.self, from: data) {
                return settings
            }
        }
        return nil
    }
}
