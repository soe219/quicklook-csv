//
//  CSVDocument.swift
//  QLQuickCSV
//
//  Document model for opening CSV/TSV files in the host app
//  Provides read-only viewing capability separate from Quick Look extension
//

import SwiftUI
import UniformTypeIdentifiers

/// UTType extensions for CSV files
extension UTType {
    static var csv: UTType {
        UTType(importedAs: "public.comma-separated-values-text")
    }

    static var tsv: UTType {
        UTType(importedAs: "public.tab-separated-values-text")
    }
}

/// Document model for CSV/TSV files
/// Read-only viewer - no editing capability
struct CSVDocument: FileDocument {
    /// Parsed CSV data
    var data: CSVData

    /// Raw file content
    var rawContent: String

    /// Original file URL (populated after opening)
    var fileURL: URL?

    /// File modification date
    var modificationDate: Date?

    /// File creation date
    var creationDate: Date?

    /// File size in bytes
    var fileSize: Int64?

    /// Readable content types
    static var readableContentTypes: [UTType] {
        [.csv, .tsv, .commaSeparatedText, .tabSeparatedText, .plainText]
    }

    /// Writable content types (none - read-only)
    static var writableContentTypes: [UTType] { [] }

    /// Initialize with empty content
    init() {
        self.rawContent = ""
        self.data = CSVData(headers: [], rows: [], delimiter: ",", hasHeaders: false, encoding: .utf8)
    }

    /// Initialize from file
    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents,
              let content = String(data: fileData, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        // Normalize line endings for consistent display
        let normalizedContent = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        self.rawContent = normalizedContent
        self.data = CSVParser.parse(normalizedContent, maxRows: Settings.shared.maxDisplayRows)

        // File attributes from FileWrapper
        let attributes = configuration.file.fileAttributes
        self.modificationDate = attributes[FileAttributeKey.modificationDate.rawValue] as? Date
        self.creationDate = attributes[FileAttributeKey.creationDate.rawValue] as? Date
        if let size = attributes[FileAttributeKey.size.rawValue] as? UInt64 {
            self.fileSize = Int64(size)
        }
    }

    /// Write file (not implemented - read-only)
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        throw CocoaError(.fileWriteNoPermission)
    }
}

/// Extension for document info
extension CSVDocument {
    /// Create document info for display
    struct DocumentInfo {
        let fileName: String
        let filePath: String
        let rowCount: Int
        let columnCount: Int
        let fileSize: Int64?
        let modificationDate: Date?

        init(document: CSVDocument, fileURL: URL?) {
            self.fileName = fileURL?.lastPathComponent ?? "Untitled.csv"
            self.filePath = fileURL?.path ?? ""
            self.rowCount = document.data.totalRows
            self.columnCount = document.data.totalColumns
            self.fileSize = document.fileSize
            self.modificationDate = document.modificationDate
        }
    }

    var info: DocumentInfo {
        DocumentInfo(document: self, fileURL: fileURL)
    }
}
