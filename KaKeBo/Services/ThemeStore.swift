//
//  Services/ThemeStore.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/19.
//

import SwiftUI
import Combine

final class ThemeStore: ObservableObject {
    @AppStorage("kakebo.theme.data") private var raw: Data = Data()
    @Published var theme: AppTheme = .init() {
        didSet { save() }
    }
    
    init() { load() }
    
    func load() {
        if let t = try? JSONDecoder().decode(AppTheme.self, from: raw) {
            theme = t
        } else {
            theme = .init()
        }
    }
    func save() {
        raw = (try? JSONEncoder().encode(theme)) ?? Data()
    }
}
