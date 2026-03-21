//
//  Models/SharedLedger.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/25.
//

import Foundation
import CloudKit

struct SharedLedger: Identifiable, Hashable {
    let id: CKRecord.ID
    
    var name: String
    var icon: String        // 絵文字 or SF Symbol 名
    var colorHex: String    // "#FFAA00" みたいな文字列
    var ownerUserId: String // iCloudの識別子 or 独自userId
    
    var createdAt: Date
    var updatedAt: Date
}

extension SharedLedger {
    static let recordType = "SharedLedger"
    static let zoneID = CKRecordZone.ID(
        zoneName: "SharedLedgerZone",
        ownerName: CKCurrentUserDefaultName
    )
    
    enum FieldKey {
        static let name = "name"
        static let icon = "icon"
        static let colorHex = "colorHex"
        static let ownerUserId = "ownerUserId"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }
    
    init?(record: CKRecord) {
        guard
            let name = record[FieldKey.name] as? String,
            let icon = record[FieldKey.icon] as? String,
            let colorHex = record[FieldKey.colorHex] as? String,
            let createdAt = record[FieldKey.createdAt] as? Date,
            let updatedAt = record[FieldKey.updatedAt] as? Date
        else {
            return nil
        }
        
        self.id = record.recordID
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
        // 旧バージョン互換: ownerUserId が未保存のケースは空文字で受け取る
        self.ownerUserId = record[FieldKey.ownerUserId] as? String ?? ""
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    func makeRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: Self.recordType, recordID: id)
        record[FieldKey.name] = name as CKRecordValue
        record[FieldKey.icon] = icon as CKRecordValue
        record[FieldKey.colorHex] = colorHex as CKRecordValue
        record[FieldKey.ownerUserId] = ownerUserId as CKRecordValue
        record[FieldKey.createdAt] = createdAt as CKRecordValue
        record[FieldKey.updatedAt] = updatedAt as CKRecordValue
        return record
    }
    
    static func new(name: String, icon: String, colorHex: String, ownerUserId: String) -> SharedLedger {
        let now = Date()
        return SharedLedger(
            id: CKRecord.ID(
                recordName: "ledger_\(UUID().uuidString)",
                zoneID: Self.zoneID
            ),
            name: name,
            icon: icon,
            colorHex: colorHex,
            ownerUserId: ownerUserId,
            createdAt: now,
            updatedAt: now
        )
    }
}
