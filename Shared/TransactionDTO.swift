//
//  TransactionDTO.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/18.
//

import Foundation

/// Shared DTO for persistence between App and Widget.
/// Matches the schema used by the widget's WTransaction.
public struct TransactionDTO: Codable, Identifiable {
    public let id: UUID
    public let date: Date
    public let amount: Int
    public let type: String   // "income" or "expense"
    public let categoryId: UUID
    public let memo: String
    
    public init(id: UUID, date: Date, amount: Int, type: String, categoryId: UUID, memo: String) {
        self.id = id
        self.date = date
        self.amount = amount
        self.type = type
        self.categoryId = categoryId
        self.memo = memo
    }
}

public extension TransactionDTO {
    /// Create DTO from app model using string mapping (lowercased).
    /// The app model must have these properties:
    /// - id: UUID
    /// - date: Date
    /// - amount: Int
    /// - type: something convertible to String via '\(type)'.lowercased()
    /// - categoryId: UUID
    /// - memo: String
    init(fromAppModel tx: Any) {
        // This initializer is a lightweight adapter to avoid importing the app model here.
        // Expect the caller to use the explicit convenience functions below instead.
        fatalError("Use explicit mapping functions defined in DataStore to avoid type coupling.")
    }
}

/// Mapping helpers that can be used by the app to convert between Transaction and TransactionDTO.
public protocol TransactionConvertible {
    var id: UUID { get }
    var date: Date { get }
    var amount: Int { get }
    var typeRawValue: String { get }
    var categoryId: UUID { get }
    var memo: String { get }
}

public extension TransactionDTO {
    /// Initialize DTO from any TransactionConvertible.
    init(from tx: TransactionConvertible) {
        self.id = tx.id
        self.date = tx.date
        self.amount = tx.amount
        self.type = tx.typeRawValue.lowercased()
        self.categoryId = tx.categoryId
        self.memo = tx.memo
    }
}

/// Example app TransactionType enum string conversion helpers
public enum TransactionTypeString: String {
    case income
    case expense
    
    init(fromRaw raw: String) {
        switch raw.lowercased() {
        case "income": self = .income
        case "expense": self = .expense
        default: self = .expense
        }
    }
}

/// This protocol can be implemented by the app Transaction model to create DTO.
public protocol TransactionDTOConvertible {
    func toDTO() -> TransactionDTO
}

public extension TransactionDTOConvertible where Self: TransactionConvertible {
    func toDTO() -> TransactionDTO {
        TransactionDTO(from: self)
    }
}

/// Helpers for mapping back from DTO to app model properties.
/// Since we cannot depend on the app model enum, provide a generic struct carrying the raw values.
public struct TransactionModelData {
    public let id: UUID
    public let date: Date
    public let amount: Int
    public let typeRawValue: String
    public let categoryId: UUID
    public let memo: String
    
    public init(id: UUID, date: Date, amount: Int, typeRawValue: String, categoryId: UUID, memo: String) {
        self.id = id
        self.date = date
        self.amount = amount
        self.typeRawValue = typeRawValue
        self.categoryId = categoryId
        self.memo = memo
    }
}

public extension TransactionDTO {
    /// Extract app model data.
    func toModelData() -> TransactionModelData {
        TransactionModelData(
            id: id,
            date: date,
            amount: amount,
            typeRawValue: type,
            categoryId: categoryId,
            memo: memo
        )
    }
}
