//
//  Item.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/09/21.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
