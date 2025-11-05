//
//  DayNotesStore.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/29.
//

import SwiftUI
import Combine

/// 日付(yyyy-MM-dd) → メモ本文 のシンプルな保存
final class DayNotesStore: ObservableObject {
    @AppStorage("kakebo.daynotes.v1") private var rawData: Data = Data()
    @Published private(set) var notes: [String: String] = [:]
    
    private let cal = Calendar.current
    private let tz  = TimeZone(identifier: "Asia/Tokyo") ?? .current
    
    init() {
        load()
    }
    
    // MARK: - Public API
    func note(for date: Date) -> String {
        notes[key(for: date)] ?? ""
    }
    func hasNote(on date: Date) -> Bool {
        !(notes[key(for: date)] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    func setNote(_ text: String, for date: Date) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notes.removeValue(forKey: key(for: date))
        } else {
            notes[key(for: date)] = trimmed
        }
        save()
        objectWillChange.send()
    }
    func removeNote(for date: Date) {
        notes.removeValue(forKey: key(for: date))
        save()
        objectWillChange.send()
    }
    
    /// 指定の“月”にメモがある日（startOfDay）を返す
    func notedDays(in month: Date) -> Set<Date> {
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
//        let end   = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        var set: Set<Date> = []
        for (k, v) in notes where !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let d = day(fromKey: k) {
                if cal.isDate(d, equalTo: start, toGranularity: .month) {
                    set.insert(cal.startOfDay(for: d))
                }
            }
        }
        return set
    }
    
    // MARK: - Persistence
    private func load() {
        guard !rawData.isEmpty,
              let dict = try? JSONDecoder().decode([String:String].self, from: rawData) else {
            notes = [:]
            return
        }
        notes = dict
    }
    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            rawData = data
        }
    }
    
    // MARK: - Key Helpers (yyyy-MM-dd JST)
    private func key(for date: Date) -> String {
        var cal = self.cal; cal.timeZone = tz
        let d = cal.startOfDay(for: date)
        let comps = cal.dateComponents([.year,.month,.day], from: d)
        let y = comps.year ?? 0, m = comps.month ?? 0, dd = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", y, m, dd)
    }
    private func day(fromKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]; comps.month = parts[1]; comps.day = parts[2]
        var cal = self.cal; cal.timeZone = tz
        return cal.date(from: comps)
    }
    
    func snippets(in month: Date, limit: Int = 8) -> [Date: String] {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: month))!
//        let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
        var out: [Date: String] = [:]
        for (k, v) in notes {
            guard let d = day(fromKey: k) else { continue }
            if cal.isDate(d, equalTo: start, toGranularity: .month) {
                let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let s = String(trimmed.prefix(limit))
                out[cal.startOfDay(for: d)] = s
            }
        }
        return out
    }

}
