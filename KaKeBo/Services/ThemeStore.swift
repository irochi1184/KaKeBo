//
//  Services/ThemeStore.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI
import Combine

final class ThemeStore: ObservableObject {
    private let defaults: UserDefaults
    private let storageKey = "kakebo.theme.data"

    @Published var theme: AppTheme = .init() {
        didSet { save() }
    }

    init(userDefaults: UserDefaults? = .appGroup) {
        self.defaults = userDefaults ?? .standard
        self.defaults.migrateIfNeeded(keys: [storageKey])
        load()
    }

    func load() {
        guard let data = defaults.migratedData(forKey: storageKey) else {
            theme = .init()
            return
        }
        if let t = try? JSONDecoder().decode(AppTheme.self, from: data) {
            theme = t
        } else {
            theme = .init()
        }
    }
    func save() {
        defaults.set((try? JSONEncoder().encode(theme)) ?? Data(), forKey: storageKey)
    }
}
