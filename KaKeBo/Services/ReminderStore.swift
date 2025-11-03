//
//  Services/ReminderStore.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

//
//  Stores/ReminderStore.swift
//  KaKeBo
//
//  Rebuilt: 2025/11/03
//

import SwiftUI
import Foundation
import Combine

final class ReminderStore: ObservableObject {
    // 公開キー：外部（SettingsViewなど）からも参照可能
    public static let storageKey = "kakebo.reminder.rules.v1"
    
    @Published var rules: [ReminderRule] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        load()
        // 並び順の安定化
        rules.sort { $0.sortOrder < $1.sortOrder }
        
        // 自動保存（不要ならコメントアウト可）
        $rules
            .dropFirst()
            .sink { [weak self] _ in self?.save() }
            .store(in: &cancellables)
    }
    
    // MARK: - 永続化
    
    func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([ReminderRule].self, from: data)
            self.rules = decoded
        } catch {
            self.rules = []
        }
    }
    
    func save() {
        do {
            let data = try JSONEncoder().encode(rules)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            // 保存失敗時は必要に応じてログ出力
        }
    }
    
    // MARK: - CRUD
    
    func update(_ rule: ReminderRule) {
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else {
            rules.append(rule)
        }
        normalizeSortOrder()
        save()
    }
    
    func delete(_ ids: [UUID]) {
        rules.removeAll { ids.contains($0.id) }
        normalizeSortOrder()
        save()
    }
    
    func move(from: IndexSet, to: Int) {
        var tmp = rules
        tmp.move(fromOffsets: from, toOffset: to)
        for (i, var r) in tmp.enumerated() {
            r.sortOrder = i
            if let idx = rules.firstIndex(where: { $0.id == r.id }) {
                rules[idx] = r
            }
        }
        rules = tmp
        save()
    }
    
    private func normalizeSortOrder() {
        for i in rules.indices {
            rules[i].sortOrder = i
        }
    }
    
    // MARK: - Static helpers（ビューから便利に使えるおまけ）
    
    /// 保存済みルールを読み出す（インスタンス不要）
    static func loadRules() -> [ReminderRule] {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return [] }
        return (try? JSONDecoder().decode([ReminderRule].self, from: data)) ?? []
    }
    
    /// 「有効 x/y 件」の文字列を返す（インスタンス不要）
    static func enabledSummaryText() -> String {
        let rules = loadRules()
        let enabled = rules.filter { $0.enabled }.count
        return "有効 \(enabled)/\(rules.count) 件"
    }
}
