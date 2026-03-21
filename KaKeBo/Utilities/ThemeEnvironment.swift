//
//  Utilities/ThemeEnvironment.swift
//  KaKeBo
//
//  Created by Codex on 2026/03/21.
//

import SwiftUI

private struct AppVisualStyleKey: EnvironmentKey {
    static let defaultValue: AppTheme.VisualStyle = .modern
}

private struct AppHomeCardStyleKey: EnvironmentKey {
    static let defaultValue: AppTheme.HomeCardStyle = .luxe
}

private struct AppIncomeColorKey: EnvironmentKey {
    static let defaultValue: Color = .green
}

private struct AppExpenseColorKey: EnvironmentKey {
    static let defaultValue: Color = .red
}

extension EnvironmentValues {
    var appVisualStyle: AppTheme.VisualStyle {
        get { self[AppVisualStyleKey.self] }
        set { self[AppVisualStyleKey.self] = newValue }
    }

    var appHomeCardStyle: AppTheme.HomeCardStyle {
        get { self[AppHomeCardStyleKey.self] }
        set { self[AppHomeCardStyleKey.self] = newValue }
    }

    var appIncomeColor: Color {
        get { self[AppIncomeColorKey.self] }
        set { self[AppIncomeColorKey.self] = newValue }
    }

    var appExpenseColor: Color {
        get { self[AppExpenseColorKey.self] }
        set { self[AppExpenseColorKey.self] = newValue }
    }
}
