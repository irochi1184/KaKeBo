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

extension EnvironmentValues {
    var appVisualStyle: AppTheme.VisualStyle {
        get { self[AppVisualStyleKey.self] }
        set { self[AppVisualStyleKey.self] = newValue }
    }

    var appHomeCardStyle: AppTheme.HomeCardStyle {
        get { self[AppHomeCardStyleKey.self] }
        set { self[AppHomeCardStyleKey.self] = newValue }
    }
}
