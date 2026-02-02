//
//  CSVParser.swift
//  QLQuickCSV
//
//  RFC 4180 compliant CSV parser with delimiter auto-detection
//  Handles quoted fields, embedded quotes, newlines in fields, and various delimiters
//

import Foundation

/// Parsed CSV data structure
struct CSVData {
    /// Column headers (first row if hasHeaders is true, or generated "Column 1", etc.)
    let headers: [String]

    /// Data rows (excludes header row)
    let rows: [[String]]

    /// Detected delimiter character
    let delimiter: Character

    /// Whether the first row was treated as headers
    let hasHeaders: Bool

    /// Detected file encoding
    let encoding: String.Encoding

    /// Total number of data rows
    var totalRows: Int { rows.count }

    /// Total number of columns
    var totalColumns: Int { headers.count }

    /// Get all values in a column by index
    func column(_ index: Int) -> [String] {
        guard index >= 0 && index < headers.count else { return [] }
        return rows.map { $0.indices.contains(index) ? $0[index] : "" }
    }

    /// Get all values in a column by header name
    func column(named name: String) -> [String] {
        guard let index = headers.firstIndex(of: name) else { return [] }
        return column(index)
    }
}

/// CSV Parser with RFC 4180 compliance
enum CSVParser {

    /// Common delimiter characters to check
    private static let possibleDelimiters: [Character] = [",", "\t", ";", "|"]

    /// Parse CSV content into structured data
    /// - Parameters:
    ///   - content: Raw CSV string content
    ///   - maxRows: Optional limit on number of rows to parse (nil = all)
    ///   - hasHeaders: Whether first row is headers (default: auto-detect)
    ///   - delimiter: Specific delimiter to use (default: auto-detect)
    /// - Returns: Parsed CSV data
    static func parse(
        _ content: String,
        maxRows: Int? = nil,
        hasHeaders: Bool? = nil,
        delimiter: Character? = nil
    ) -> CSVData {
        // Handle empty content
        guard !content.isEmpty else {
            return CSVData(
                headers: [],
                rows: [],
                delimiter: ",",
                hasHeaders: false,
                encoding: .utf8
            )
        }

        // Normalize line endings: convert \r\n and \r to \n
        let normalizedContent = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Detect or use provided delimiter
        let detectedDelimiter = delimiter ?? detectDelimiter(normalizedContent)

        // Parse all rows using normalized content
        let allRows = parseRows(normalizedContent, delimiter: detectedDelimiter, maxRows: maxRows.map { $0 + 1 })

        guard !allRows.isEmpty else {
            return CSVData(
                headers: [],
                rows: [],
                delimiter: detectedDelimiter,
                hasHeaders: false,
                encoding: .utf8
            )
        }

        // Determine if first row is headers
        let firstRowIsHeaders = hasHeaders ?? detectIfFirstRowIsHeaders(allRows)

        // Extract headers and data rows
        let headers: [String]
        let dataRows: [[String]]

        if firstRowIsHeaders && !allRows.isEmpty {
            headers = allRows[0]
            dataRows = Array(allRows.dropFirst())
        } else {
            // Generate column names
            let columnCount = allRows.map(\.count).max() ?? 0
            headers = (1...columnCount).map { "Column \($0)" }
            dataRows = allRows
        }

        // Apply maxRows limit to data rows
        let limitedRows: [[String]]
        if let max = maxRows, dataRows.count > max {
            limitedRows = Array(dataRows.prefix(max))
        } else {
            limitedRows = dataRows
        }

        return CSVData(
            headers: headers,
            rows: limitedRows,
            delimiter: detectedDelimiter,
            hasHeaders: firstRowIsHeaders,
            encoding: .utf8
        )
    }

    /// Detect the most likely delimiter by analyzing the content
    static func detectDelimiter(_ content: String) -> Character {
        // Get first few lines for analysis
        let lines = content.components(separatedBy: .newlines)
            .prefix(10)
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return "," }

        // Score each delimiter by consistency of column counts
        var bestDelimiter: Character = ","
        var bestScore: Double = 0

        for delimiter in possibleDelimiters {
            // Count columns per line with this delimiter
            let counts = lines.map { line -> Int in
                countFields(in: line, delimiter: delimiter)
            }

            guard let firstCount = counts.first, firstCount > 1 else { continue }

            // Score based on:
            // 1. Consistency (all lines have same column count)
            // 2. Number of columns (prefer more columns if consistent)
            let allSame = counts.allSatisfy { $0 == firstCount }
            let variance = counts.map { Double(abs($0 - firstCount)) }.reduce(0, +) / Double(counts.count)

            let consistencyScore = allSame ? 1.0 : max(0, 1.0 - variance / Double(firstCount))
            let columnScore = min(Double(firstCount) / 10.0, 1.0)
            let score = consistencyScore * 0.7 + columnScore * 0.3

            if score > bestScore {
                bestScore = score
                bestDelimiter = delimiter
            }
        }

        return bestDelimiter
    }

    /// Count the number of fields in a line (respecting quotes)
    private static func countFields(in line: String, delimiter: Character) -> Int {
        var count = 1
        var inQuotes = false
        var prevChar: Character? = nil

        for char in line {
            if char == "\"" && prevChar != "\\" {
                inQuotes.toggle()
            } else if char == delimiter && !inQuotes {
                count += 1
            }
            prevChar = char
        }

        return count
    }

    /// Detect if the first row looks like headers
    /// Headers typically have shorter, text-only values that look like names
    private static func detectIfFirstRowIsHeaders(_ rows: [[String]]) -> Bool {
        guard rows.count >= 2, let firstRow = rows.first else { return true }

        // Check if first row values look like header names:
        // 1. All non-empty
        // 2. No pure numbers
        // 3. Relatively short
        // 4. Different pattern from subsequent rows

        let allNonEmpty = firstRow.allSatisfy { !$0.isEmpty }
        let noPureNumbers = firstRow.allSatisfy { Double($0) == nil }
        let reasonablyShort = firstRow.allSatisfy { $0.count < 100 }

        // Check if data rows have different characteristics (e.g., more numbers)
        let dataRows = Array(rows.dropFirst().prefix(5))
        let dataHasNumbers = dataRows.contains { row in
            row.contains { Double($0) != nil }
        }

        return allNonEmpty && noPureNumbers && reasonablyShort && (dataHasNumbers || rows.count <= 1)
    }

    /// Parse content into rows using RFC 4180 rules
    private static func parseRows(_ content: String, delimiter: Character, maxRows: Int?) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var i = content.startIndex

        while i < content.endIndex {
            let char = content[i]

            if inQuotes {
                if char == "\"" {
                    // Check for escaped quote ("")
                    let nextIndex = content.index(after: i)
                    if nextIndex < content.endIndex && content[nextIndex] == "\"" {
                        // Escaped quote - add single quote and skip next
                        currentField.append("\"")
                        i = nextIndex
                    } else {
                        // End of quoted field
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    // Start of quoted field
                    inQuotes = true
                } else if char == delimiter {
                    // Field separator
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                } else if char == "\r" {
                    // Possible CRLF line ending
                    let nextIndex = content.index(after: i)
                    if nextIndex < content.endIndex && content[nextIndex] == "\n" {
                        i = nextIndex
                    }
                    // End of row
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                        if let max = maxRows, rows.count >= max {
                            return rows
                        }
                    }
                    currentRow = []
                    currentField = ""
                } else if char == "\n" {
                    // End of row
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    if !currentRow.allSatisfy({ $0.isEmpty }) {
                        rows.append(currentRow)
                        if let max = maxRows, rows.count >= max {
                            return rows
                        }
                    }
                    currentRow = []
                    currentField = ""
                } else {
                    currentField.append(char)
                }
            }

            i = content.index(after: i)
        }

        // Handle last field and row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentRow.allSatisfy({ $0.isEmpty }) {
                rows.append(currentRow)
            }
        }

        // Normalize row lengths
        let maxColumns = rows.map(\.count).max() ?? 0
        return rows.map { row in
            if row.count < maxColumns {
                return row + Array(repeating: "", count: maxColumns - row.count)
            }
            return row
        }
    }

    /// Parse CSV from a file URL
    /// - Parameters:
    ///   - url: File URL to read
    ///   - maxRows: Optional limit on number of rows
    /// - Returns: Parsed CSV data or nil if file cannot be read
    static func parse(contentsOf url: URL, maxRows: Int? = nil) -> CSVData? {
        // Try common encodings
        let encodings: [String.Encoding] = [.utf8, .utf16, .windowsCP1252, .isoLatin1]

        for encoding in encodings {
            if let content = try? String(contentsOf: url, encoding: encoding) {
                let data = parse(content, maxRows: maxRows)
                // Create new CSVData with correct encoding
                return CSVData(
                    headers: data.headers,
                    rows: data.rows,
                    delimiter: data.delimiter,
                    hasHeaders: data.hasHeaders,
                    encoding: encoding
                )
            }
        }

        return nil
    }
}

// MARK: - Formatting Extensions

extension CSVData {
    /// Format as markdown table
    func toMarkdown(maxRows: Int? = nil) -> String {
        guard !headers.isEmpty else { return "" }

        let displayRows = maxRows.map { Array(rows.prefix($0)) } ?? rows

        var lines: [String] = []

        // Header row
        lines.append("| " + headers.joined(separator: " | ") + " |")

        // Separator row
        lines.append("| " + headers.map { _ in "---" }.joined(separator: " | ") + " |")

        // Data rows
        for row in displayRows {
            let paddedRow = headers.indices.map { i in
                i < row.count ? row[i] : ""
            }
            lines.append("| " + paddedRow.joined(separator: " | ") + " |")
        }

        if let max = maxRows, rows.count > max {
            lines.append("| ... | \(rows.count - max) more rows |")
        }

        return lines.joined(separator: "\n")
    }

    /// Format as JSON array of objects
    func toJSON(maxRows: Int? = nil, prettyPrint: Bool = true) -> String {
        let displayRows = maxRows.map { Array(rows.prefix($0)) } ?? rows

        var objects: [[String: Any]] = []
        for row in displayRows {
            var obj: [String: String] = [:]
            for (i, header) in headers.enumerated() {
                obj[header] = i < row.count ? row[i] : ""
            }
            objects.append(obj)
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: objects,
            options: prettyPrint ? [.prettyPrinted, .sortedKeys] : []
        ),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }

        return json
    }

    /// Format as SQL INSERT statements
    func toSQL(tableName: String = "data", maxRows: Int? = nil) -> String {
        guard !headers.isEmpty else { return "" }

        let displayRows = maxRows.map { Array(rows.prefix($0)) } ?? rows

        var lines: [String] = []

        // Create table statement
        let columnDefs = headers.map { "\"\($0)\" TEXT" }.joined(separator: ", ")
        lines.append("CREATE TABLE IF NOT EXISTS \"\(tableName)\" (\(columnDefs));")
        lines.append("")

        // Insert statements
        let columnNames = headers.map { "\"\($0)\"" }.joined(separator: ", ")

        for row in displayRows {
            let values = headers.indices.map { i -> String in
                let value = i < row.count ? row[i] : ""
                // Escape single quotes
                let escaped = value.replacingOccurrences(of: "'", with: "''")
                return "'\(escaped)'"
            }.joined(separator: ", ")

            lines.append("INSERT INTO \"\(tableName)\" (\(columnNames)) VALUES (\(values));")
        }

        return lines.joined(separator: "\n")
    }
}
