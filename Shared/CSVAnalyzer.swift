//
//  CSVAnalyzer.swift
//  QLQuickCSV
//
//  Column type detection, statistics calculation, and data analysis
//  Provides insights into CSV data structure and content
//

import Foundation

/// Detected column data type
enum ColumnType: String, CaseIterable {
    case text = "text"
    case integer = "integer"
    case decimal = "decimal"
    case date = "date"
    case boolean = "boolean"
    case empty = "empty"
    case mixed = "mixed"

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .text: return "Text"
        case .integer: return "Integer"
        case .decimal: return "Decimal"
        case .date: return "Date"
        case .boolean: return "Boolean"
        case .empty: return "Empty"
        case .mixed: return "Mixed"
        }
    }

    /// SF Symbol for the type
    var symbolName: String {
        switch self {
        case .text: return "textformat"
        case .integer: return "number"
        case .decimal: return "number.circle"
        case .date: return "calendar"
        case .boolean: return "checkmark.circle"
        case .empty: return "circle.dashed"
        case .mixed: return "questionmark.circle"
        }
    }

    /// CSS color for type badge
    var badgeColor: String {
        switch self {
        case .text: return "#6c757d"      // gray
        case .integer: return "#0d6efd"   // blue
        case .decimal: return "#198754"   // green
        case .date: return "#6610f2"      // purple
        case .boolean: return "#dc3545"   // red
        case .empty: return "#adb5bd"     // light gray
        case .mixed: return "#fd7e14"     // orange
        }
    }
}

/// Statistics for a single column
struct ColumnStats {
    /// Detected data type
    let type: ColumnType

    /// Total number of values
    let count: Int

    /// Number of non-empty values
    let nonEmptyCount: Int

    /// Number of distinct values
    let distinctCount: Int

    /// Number of empty/null values
    let nullCount: Int

    /// Minimum value (for numeric/date types)
    let min: String?

    /// Maximum value (for numeric/date types)
    let max: String?

    /// Sum of values (for numeric types)
    let sum: Double?

    /// Average of values (for numeric types)
    let average: Double?

    /// Sample of distinct values with counts (sorted by frequency)
    let topValues: [(value: String, count: Int)]

    /// Percentage of non-empty values
    var fillRate: Double {
        guard count > 0 else { return 0 }
        return Double(nonEmptyCount) / Double(count) * 100
    }
}

/// CSV column and data analyzer
enum CSVAnalyzer {

    // MARK: - Date Formats

    /// Common date format patterns to try
    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss",
            "MM/dd/yyyy",
            "dd/MM/yyyy",
            "M/d/yyyy",
            "MM-dd-yyyy",
            "dd-MM-yyyy",
            "yyyy/MM/dd",
            "MMM d, yyyy",
            "MMMM d, yyyy"
        ]

        return formats.map { format -> DateFormatter in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }
    }()

    // MARK: - Type Detection

    /// Detect the type of a single value
    static func detectType(_ value: String) -> ColumnType {
        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Empty check
        if trimmed.isEmpty {
            return .empty
        }

        // Boolean check
        let lowerValue = trimmed.lowercased()
        if ["true", "false", "yes", "no", "1", "0", "y", "n"].contains(lowerValue) {
            return .boolean
        }

        // Integer check (including negative numbers)
        if let _ = Int(trimmed) {
            return .integer
        }

        // Decimal check (including negative and with comma as decimal separator)
        let normalizedForDouble = trimmed.replacingOccurrences(of: ",", with: "")
        if let _ = Double(normalizedForDouble) {
            return .decimal
        }

        // Date check
        for formatter in dateFormatters {
            if formatter.date(from: trimmed) != nil {
                return .date
            }
        }

        // Default to text
        return .text
    }

    /// Analyze a column and determine its overall type
    static func analyzeColumn(_ values: [String]) -> ColumnStats {
        guard !values.isEmpty else {
            return ColumnStats(
                type: .empty,
                count: 0,
                nonEmptyCount: 0,
                distinctCount: 0,
                nullCount: 0,
                min: nil,
                max: nil,
                sum: nil,
                average: nil,
                topValues: []
            )
        }

        // Count type occurrences
        var typeCounts: [ColumnType: Int] = [:]
        var numericValues: [Double] = []
        var nonEmptyValues: [String] = []
        var valueCounts: [String: Int] = [:]

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespaces)

            // Track value frequencies
            valueCounts[trimmed, default: 0] += 1

            let type = detectType(value)
            typeCounts[type, default: 0] += 1

            if type != .empty {
                nonEmptyValues.append(trimmed)
            }

            // Collect numeric values for statistics
            if type == .integer || type == .decimal {
                let normalized = trimmed.replacingOccurrences(of: ",", with: "")
                if let num = Double(normalized) {
                    numericValues.append(num)
                }
            }
        }

        // Determine overall type
        let nonEmptyTypes = typeCounts.filter { $0.key != .empty }
        let overallType: ColumnType

        if nonEmptyTypes.isEmpty {
            overallType = .empty
        } else if nonEmptyTypes.count == 1, let type = nonEmptyTypes.keys.first {
            overallType = type
        } else if nonEmptyTypes.count == 2 && nonEmptyTypes.keys.contains(.integer) && nonEmptyTypes.keys.contains(.decimal) {
            // Integers and decimals together = decimal
            overallType = .decimal
        } else {
            // Multiple types = mixed
            overallType = .mixed
        }

        // Calculate numeric statistics
        var min: String? = nil
        var max: String? = nil
        var sum: Double? = nil
        var average: Double? = nil

        if !numericValues.isEmpty {
            let minVal = numericValues.min()!
            let maxVal = numericValues.max()!
            let sumVal = numericValues.reduce(0, +)

            min = formatNumber(minVal)
            max = formatNumber(maxVal)
            sum = sumVal
            average = sumVal / Double(numericValues.count)
        } else if overallType == .date {
            // For dates, find min/max as strings
            let sortedNonEmpty = nonEmptyValues.sorted()
            min = sortedNonEmpty.first
            max = sortedNonEmpty.last
        } else if overallType == .text || overallType == .mixed {
            // For text, use alphabetical min/max
            let sortedNonEmpty = nonEmptyValues.sorted()
            min = sortedNonEmpty.first
            max = sortedNonEmpty.last
        }

        // Get top values by frequency
        let topValues = valueCounts
            .sorted { $0.value > $1.value }
            .prefix(20)
            .map { (value: $0.key, count: $0.value) }

        return ColumnStats(
            type: overallType,
            count: values.count,
            nonEmptyCount: nonEmptyValues.count,
            distinctCount: Set(nonEmptyValues).count,
            nullCount: typeCounts[.empty, default: 0],
            min: min,
            max: max,
            sum: sum,
            average: average,
            topValues: Array(topValues)
        )
    }

    /// Analyze all columns in CSV data
    static func analyzeCSV(_ data: CSVData) -> [String: ColumnStats] {
        var results: [String: ColumnStats] = [:]

        for (i, header) in data.headers.enumerated() {
            let columnValues = data.column(i)
            results[header] = analyzeColumn(columnValues)
        }

        return results
    }

    // MARK: - Distinct Values

    /// Get distinct values with their counts for a column
    static func getDistinctValues(_ values: [String], limit: Int = 100) -> [(value: String, count: Int)] {
        var counts: [String: Int] = [:]

        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            counts[trimmed, default: 0] += 1
        }

        return counts
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .map { (value: $0.key, count: $0.value) }
    }

    // MARK: - Helpers

    /// Format a number for display (remove unnecessary decimals)
    private static func formatNumber(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        } else if abs(value) >= 1000 {
            return String(format: "%.2f", value)
        } else {
            return String(format: "%.4f", value)
                .replacingOccurrences(of: "\\.?0+$", with: "", options: .regularExpression)
        }
    }
}

// MARK: - CSV Data Extensions

extension CSVData {
    /// Get statistics for all columns
    var columnStats: [String: ColumnStats] {
        CSVAnalyzer.analyzeCSV(self)
    }

    /// Get statistics for a specific column
    func statsForColumn(_ name: String) -> ColumnStats? {
        guard let index = headers.firstIndex(of: name) else { return nil }
        return CSVAnalyzer.analyzeColumn(column(index))
    }

    /// Get statistics for a column by index
    func statsForColumn(at index: Int) -> ColumnStats? {
        guard index >= 0 && index < headers.count else { return nil }
        return CSVAnalyzer.analyzeColumn(column(index))
    }

    /// Summary description of the CSV
    var summary: String {
        let delimiter = self.delimiter == "\t" ? "TSV" : "CSV"
        return "\(totalRows.formatted()) rows × \(totalColumns) columns (\(delimiter))"
    }
}

// MARK: - Number Formatting

extension ColumnStats {
    /// Formatted average string
    var formattedAverage: String? {
        guard let avg = average else { return nil }
        if abs(avg) >= 1000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: avg))
        }
        return String(format: "%.2f", avg)
    }

    /// Formatted sum string
    var formattedSum: String? {
        guard let s = sum else { return nil }
        if abs(s) >= 1000 {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter.string(from: NSNumber(value: s))
        }
        return String(format: "%.2f", s)
    }
}
