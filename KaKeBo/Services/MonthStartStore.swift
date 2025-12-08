//
//  Services/MonthStartStore.swift
//  KaKeBo
//
//  Created by OpenAI on 2025/02/23.
//

import Foundation
import Combine

final class MonthStartStore: ObservableObject {
    @Published var settings: MonthStartSettings {
        didSet { persist() }
    }

    private let storageKey = "kakebo.monthStart.settings"
    private let userDefaults: UserDefaults
    private let holidayProvider = JapaneseHolidayProvider()

    init(userDefaults: UserDefaults? = UserDefaults(suiteName: AppGroup.id)) {
        self.userDefaults = userDefaults ?? .standard
        if let saved = Self.load(from: self.userDefaults) {
            settings = saved
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
            userDefaults.set(data, forKey: storageKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> MonthStartSettings? {
        guard let data = defaults.data(forKey: "kakebo.monthStart.settings") else { return nil }
        return try? JSONDecoder().decode(MonthStartSettings.self, from: data)
    }
}
