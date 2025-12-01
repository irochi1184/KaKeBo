//
//  Models/SharedTransaction.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/11/25.
//

import Foundation
import CloudKit

enum SharedTransactionType: String, CaseIterable {
    case expense  // 支出
    case income   // 収入
}

struct SharedTransaction: Identifiable, Hashable {
    let id: CKRecord.ID
    
    var ledgerId: CKRecord.ID
    
    var amount: Int
    var date: Date
    var type: SharedTransactionType
    var memo: String?
    
    var categoryId: CKRecord.ID?
    var categoryName: String
    var categoryColorHex: String
    
    var createdByUserId: String
    var createdAt: Date
    var updatedAt: Date
}

extension SharedTransaction {
    static let recordType = "SharedTransaction"
    
    enum FieldKey {
        static let ledgerRef = "ledger"
        static let amount = "amount"
        static let date = "date"
        static let type = "type"
        static let memo = "memo"
        static let categoryRef = "category"
        static let categoryName = "categoryName"
        static let categoryColorHex = "categoryColorHex"
        static let createdByUserId = "createdByUserId"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }
    
    init?(record: CKRecord) {
        guard
            let ledgerRef = record[FieldKey.ledgerRef] as? CKRecord.Reference,
            let amount = record[FieldKey.amount] as? Int,
            let date = record[FieldKey.date] as? Date,
            let typeRaw = record[FieldKey.type] as? String,
            let type = SharedTransactionType(rawValue: typeRaw),
            let createdByUserId = record[FieldKey.createdByUserId] as? String,
            let createdAt = record[FieldKey.createdAt] as? Date,
            let updatedAt = record[FieldKey.updatedAt] as? Date
        else {
            return nil
        }
        
        self.id = record.recordID
        self.ledgerId = ledgerRef.recordID
        self.amount = amount
        self.date = date
        self.type = type
        self.memo = record[FieldKey.memo] as? String
        
        // カテゴリ参照は任意
        if let categoryRef = record[FieldKey.categoryRef] as? CKRecord.Reference {
            self.categoryId = categoryRef.recordID
        } else {
            self.categoryId = nil
        }
        
        self.categoryName = record[FieldKey.categoryName] as? String ?? "未分類"
        self.categoryColorHex = record[FieldKey.categoryColorHex] as? String ?? "#FF9500"
        
        self.createdByUserId = createdByUserId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    func makeRecord(existing: CKRecord? = nil) -> CKRecord {
        let record = existing ?? CKRecord(recordType: Self.recordType, recordID: id)
        let ledgerRef = CKRecord.Reference(recordID: ledgerId, action: .deleteSelf)
        
        record[FieldKey.ledgerRef] = ledgerRef
        record[FieldKey.amount] = amount as CKRecordValue
        record[FieldKey.date] = date as CKRecordValue
        record[FieldKey.type] = type.rawValue as CKRecordValue
        record[FieldKey.memo] = memo as CKRecordValue?
        
        if let categoryId {
            let catRef = CKRecord.Reference(recordID: categoryId, action: .none)
            record[FieldKey.categoryRef] = catRef
        } else {
            record[FieldKey.categoryRef] = nil
        }
        record[FieldKey.categoryName] = categoryName as CKRecordValue
        record[FieldKey.categoryColorHex] = categoryColorHex as CKRecordValue
        
        record[FieldKey.createdByUserId] = createdByUserId as CKRecordValue
        record[FieldKey.createdAt] = createdAt as CKRecordValue
        record[FieldKey.updatedAt] = updatedAt as CKRecordValue
        
        return record
    }
    
    static func new(
        ledgerId: CKRecord.ID,
        amount: Int,
        date: Date,
        type: SharedTransactionType,
        memo: String?,
        categoryId: CKRecord.ID?,
        categoryName: String,
        categoryColorHex: String,
        createdByUserId: String
    ) -> SharedTransaction {
        let now = Date()
        return SharedTransaction(
            id: CKRecord.ID(recordName: UUID().uuidString),
            ledgerId: ledgerId,
            amount: amount,
            date: date,
            type: type,
            memo: memo,
            categoryId: categoryId,
            categoryName: categoryName,
            categoryColorHex: categoryColorHex,
            createdByUserId: createdByUserId,
            createdAt: now,
            updatedAt: now
        )
    }
}
