//
//  Services/ReminderStore.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI
import Foundation
import Combine

final class ReminderStore: ObservableObject {
    static let storageKey = "kakebo.reminders.rules"
    
    @Published var rules: [ReminderRule] = []
    
    init() { load() }
    
    // MARK: Load / Save
    func load() {
        let data = UserDefaults.standard.data(forKey: Self.storageKey) ?? Data()
        if let items = try? JSONDecoder().decode([ReminderRule].self, from: data) {
            self.rules = items.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            self.rules = []
        }
    }
    
    func save() {
        // 並び順を正規化
        for i in rules.indices { rules[i].sortOrder = i }
        let data = (try? JSONEncoder().encode(rules)) ?? Data()
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
    
    // MARK: CRUD
    func add(_ rule: ReminderRule) { rules.append(rule); save() }
    func update(_ rule: ReminderRule) {
        guard let i = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[i] = rule; save()
    }
    func delete(_ ids: [UUID]) { rules.removeAll { ids.contains($0.id) }; save() }
    func move(from: IndexSet, to: Int) { rules.move(fromOffsets: from, toOffset: to); save() }
}
