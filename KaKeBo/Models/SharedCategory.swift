//
//  Models/SharedCategory.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/26.
//

import Foundation
import CloudKit
import SwiftUI

struct SharedCategory: Identifiable, Hashable {
    let id: CKRecord.ID
    
    var ledgerId: CKRecord.ID
    var name: String
    var colorHex: String
    var icon: String        // 絵文字 or SF Symbol 名（お好みで）
    var sortOrder: Int      // 並び順
    
    var createdAt: Date
    var updatedAt: Date
}

extension SharedCategory {
    static let recordType = "SharedCategory"
    
    enum FieldKey {
        static let ledgerRef = "ledger"
        static let name = "name"
        static let colorHex = "colorHex"
        static let icon = "icon"
        static let sortOrder = "sortOrder"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }
    
    init?(record: CKRecord) {
        guard
            let ref = record[FieldKey.ledgerRef] as? CKRecord.Reference,
            let name = record[FieldKey.name] as? String,
            let colorHex = record[FieldKey.colorHex] as? String,
            let icon = record[FieldKey.icon] as? String,
            let sortOrder = record[FieldKey.sortOrder] as? Int,
            let createdAt = record[FieldKey.createdAt] as? Date,
            let updatedAt = record[FieldKey.updatedAt] as? Date
        else {
            return nil
        }
        
        self.id = record.recordID
        self.ledgerId = ref.recordID
        self.name = name
        self.colorHex = colorHex
        self.icon = icon
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    func makeRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: Self.recordType, recordID: id)
        let ledgerRef = CKRecord.Reference(recordID: ledgerId, action: .deleteSelf)
        record.parent = CKRecord.Reference(recordID: ledgerId, action: .none)
        
        record[FieldKey.ledgerRef] = ledgerRef
        record[FieldKey.name] = name as CKRecordValue
        record[FieldKey.colorHex] = colorHex as CKRecordValue
        record[FieldKey.icon] = icon as CKRecordValue
        record[FieldKey.sortOrder] = sortOrder as CKRecordValue
        record[FieldKey.createdAt] = createdAt as CKRecordValue
        record[FieldKey.updatedAt] = updatedAt as CKRecordValue
        
        return record
    }
    
    static func new(
        ledgerId: CKRecord.ID,
        name: String,
        colorHex: String,
        icon: String,
        sortOrder: Int
    ) -> SharedCategory {
        let now = Date()
        return SharedCategory(
            id: CKRecord.ID(
                recordName: "category_\(UUID().uuidString)",
                zoneID: ledgerId.zoneID
            ),
            ledgerId: ledgerId,
            name: name,
            colorHex: colorHex,
            icon: icon,
            sortOrder: sortOrder,
            createdAt: now,
            updatedAt: now
        )
    }
}
