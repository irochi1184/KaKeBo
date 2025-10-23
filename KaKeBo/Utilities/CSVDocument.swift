//
//  Utilities/CSVDocument.swift
//  KaKeBo
//
//  Created by 有田健一郎 on 2025/10/23.
//

import SwiftUI
import UniformTypeIdentifiers

struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    static var writableContentTypes: [UTType] { [.commaSeparatedText] }
    
    var data: Data
    
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = d
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        .init(regularFileWithContents: data)
    }
}
