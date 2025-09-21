//
//  Haptics.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum Haptics {
    static func tap() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }
}
