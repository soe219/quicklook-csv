//
//  HTMLGenerator.swift
//  QLQuickCSV
//
//  Generates HTML table preview with interactive features
//  Supports sorting, filtering, column selection, statistics panel, and multiple view modes
//
//  Security note: All data displayed is from local CSV files only.
//  The innerHTML usage is intentional for rendering pre-sanitized content.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum HTMLGenerator {

    /// View mode for the CSV display
    enum ViewMode: String {
        case table = "table"
        case markdown = "markdown"
        case json = "json"
    }

    // MARK: - Main Generation

    /// Generate complete HTML preview for CSV data
    static func generate(
        data: CSVData,
        fileName: String,
        filePath: String?,
        fileSize: Int64? = nil,
        modificationDate: Date? = nil,
        githubURL: String? = nil,
        rawContent: String? = nil,
        maxDisplayRows: Int = 1000
    ) -> String {
        let isDarkMode = isDarkModeEnabled()
        let theme = isDarkMode ? darkTheme : lightTheme

        // Analyze columns for statistics
        let stats = CSVAnalyzer.analyzeCSV(data)

        // Limit rows for display
        let displayRows = Array(data.rows.prefix(maxDisplayRows))
        let hasMoreRows = data.rows.count > maxDisplayRows

        // Build HTML
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(escapeHTML(fileName))</title>
            <style>
        \(generateCSS(theme: theme))
            </style>
        </head>
        <body class="\(isDarkMode ? "dark" : "light")">
            <div class="container">
        \(generateHeader(fileName: fileName, filePath: filePath, data: data, fileSize: fileSize, modificationDate: modificationDate, githubURL: githubURL, hasMoreRows: hasMoreRows, maxDisplayRows: maxDisplayRows))
        \(generateToolbar(hasHeaders: data.hasHeaders))
        \(generateStatsPanel(stats: stats, data: data))
        \(generateTableView(data: data, displayRows: displayRows, stats: stats))
        \(generateMarkdownView(data: data, displayRows: displayRows))
        \(generateJSONView(data: data, displayRows: displayRows))
        \(generateTXTView(rawContent: rawContent, data: data))
        \(generateFilterBar())
            </div>
            <script>
        \(generateMarkdownRenderer())
            </script>
            <script>
        \(generateJavaScript(data: data, displayRows: displayRows, stats: stats))
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Markdown Renderer (Minimal Table Parser)

    private static func generateMarkdownRenderer() -> String {
        // Minimal markdown table renderer for CSV data
        // Parses markdown table format and converts to HTML
        return """
        function renderMarkdownTable(markdown) {
            const lines = markdown.trim().split('\\n');
            if (lines.length < 2) return '<p>' + markdown + '</p>';

            // Find table start
            let tableStart = -1;
            for (let i = 0; i < lines.length; i++) {
                if (lines[i].trim().startsWith('|')) {
                    tableStart = i;
                    break;
                }
            }
            if (tableStart === -1) return '<pre>' + markdown + '</pre>';

            // Parse header
            const headerLine = lines[tableStart];
            const headers = headerLine.split('|').filter(c => c.trim()).map(c => c.trim());

            // Skip separator line (line with dashes)
            const dataStart = tableStart + 2;
            if (dataStart >= lines.length) {
                return '<table><thead><tr>' + headers.map(h => '<th>' + escapeHtml(h) + '</th>').join('') + '</tr></thead></table>';
            }

            // Parse data rows
            const rows = [];
            for (let i = dataStart; i < lines.length; i++) {
                const line = lines[i].trim();
                if (!line || !line.startsWith('|')) continue;
                const cells = line.split('|').filter(c => c !== '').map(c => c.trim());
                if (cells.length > 0) rows.push(cells);
            }

            // Build HTML table
            let html = '<table>';
            html += '<thead><tr>' + headers.map(h => '<th>' + escapeHtml(h) + '</th>').join('') + '</tr></thead>';
            html += '<tbody>';
            rows.forEach(row => {
                html += '<tr>';
                for (let i = 0; i < headers.length; i++) {
                    const cell = row[i] || '';
                    html += '<td>' + escapeHtml(cell) + '</td>';
                }
                html += '</tr>';
            });
            html += '</tbody></table>';

            return html;
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }
        """
    }

    // MARK: - Theme Colors

    struct Theme {
        let background: String
        let secondaryBackground: String
        let text: String
        let secondaryText: String
        let border: String
        let headerBackground: String
        let rowHover: String
        let selectedRow: String
        let selectedColumn: String
        let linkColor: String
        let buttonBackground: String
        let buttonHover: String
        let accent: String
    }

    private static let lightTheme = Theme(
        background: "#ffffff",
        secondaryBackground: "#f8f9fa",
        text: "#212529",
        secondaryText: "#6c757d",
        border: "#dee2e6",
        headerBackground: "#e9ecef",
        rowHover: "#f1f3f5",
        selectedRow: "#cfe2ff",
        selectedColumn: "#e7f1ff",
        linkColor: "#0d6efd",
        buttonBackground: "#e9ecef",
        buttonHover: "#dee2e6",
        accent: "#0d6efd"
    )

    private static let darkTheme = Theme(
        background: "#1a1a1a",
        secondaryBackground: "#2d2d2d",
        text: "#e9ecef",
        secondaryText: "#adb5bd",
        border: "#495057",
        headerBackground: "#343a40",
        rowHover: "#2d2d2d",
        selectedRow: "#1e3a5f",
        selectedColumn: "#1e3a5f",
        linkColor: "#6ea8fe",
        buttonBackground: "#495057",
        buttonHover: "#5c636a",
        accent: "#6ea8fe"
    )

    // MARK: - CSS Generation

    private static func generateCSS(theme: Theme) -> String {
        return """
        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif;
            font-size: 13px;
            line-height: 1.5;
            color: \(theme.text);
            background: \(theme.background);
            -webkit-font-smoothing: antialiased;
        }

        .container {
            max-width: 100%;
            padding: 16px;
        }

        /* Header */
        .header {
            margin-bottom: 16px;
            padding-bottom: 16px;
            border-bottom: 1px solid \(theme.border);
        }

        .header h1 {
            font-size: 18px;
            font-weight: 600;
            margin-bottom: 4px;
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .header h1 .icon {
            font-size: 20px;
        }

        .header-meta {
            color: \(theme.secondaryText);
            font-size: 12px;
            display: flex;
            flex-wrap: wrap;
            gap: 16px;
            margin-top: 8px;
        }

        .header-meta span {
            display: flex;
            align-items: center;
            gap: 4px;
        }

        .header-actions {
            display: flex;
            gap: 8px;
            margin-top: 12px;
        }

        /* Buttons */
        .btn {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            padding: 6px 12px;
            font-size: 12px;
            font-weight: 500;
            color: \(theme.text);
            background: \(theme.buttonBackground);
            border: 1px solid \(theme.border);
            border-radius: 6px;
            cursor: pointer;
            transition: all 0.15s ease;
        }

        .btn:hover {
            background: \(theme.buttonHover);
        }

        .btn.active {
            background: \(theme.linkColor);
            color: #ffffff;
            border-color: \(theme.linkColor);
        }

        .btn-group {
            display: inline-flex;
            border-radius: 6px;
            overflow: hidden;
        }

        .btn-group .btn {
            border-radius: 0;
            margin-left: -1px;
        }

        .btn-group .btn:first-child {
            border-radius: 6px 0 0 6px;
            margin-left: 0;
        }

        .btn-group .btn:last-child {
            border-radius: 0 6px 6px 0;
        }

        /* Toolbar */
        .toolbar {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 12px;
            padding: 8px 12px;
            background: \(theme.secondaryBackground);
            border-radius: 8px;
        }

        .toolbar-left, .toolbar-right {
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .header-toggle {
            display: flex;
            align-items: center;
            gap: 6px;
            font-size: 12px;
            color: \(theme.secondaryText);
            cursor: pointer;
            padding: 6px 10px;
            background: \(theme.background);
            border: 1px solid \(theme.border);
            border-radius: 6px;
            user-select: none;
        }

        .header-toggle:hover {
            border-color: \(theme.accent);
        }

        .header-toggle input[type="checkbox"] {
            margin: 0;
            cursor: pointer;
        }

        .search-box {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 6px 12px;
            background: \(theme.background);
            border: 1px solid \(theme.border);
            border-radius: 6px;
        }

        .search-box input {
            border: none;
            outline: none;
            background: transparent;
            color: \(theme.text);
            font-size: 12px;
            width: 200px;
        }

        .search-box input::placeholder {
            color: \(theme.secondaryText);
        }

        /* Stats Panel */
        .stats-panel {
            display: none;
            position: fixed;
            right: 16px;
            top: 80px;
            width: 280px;
            max-height: calc(100vh - 100px);
            overflow-y: auto;
            background: \(theme.secondaryBackground);
            border: 1px solid \(theme.border);
            border-radius: 8px;
            padding: 16px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
            z-index: 100;
        }

        .stats-panel.visible {
            display: block;
        }

        .stats-panel h3 {
            font-size: 14px;
            font-weight: 600;
            margin-bottom: 12px;
            padding-bottom: 8px;
            border-bottom: 1px solid \(theme.border);
        }

        .stats-row {
            display: flex;
            justify-content: space-between;
            padding: 4px 0;
            font-size: 12px;
        }

        .stats-row .label {
            color: \(theme.secondaryText);
        }

        .stats-row .value {
            font-weight: 500;
            font-family: 'SF Mono', Menlo, monospace;
        }

        .top-values {
            margin-top: 16px;
        }

        .top-values h4 {
            font-size: 12px;
            font-weight: 600;
            margin-bottom: 8px;
            color: \(theme.secondaryText);
        }

        .value-bar {
            display: flex;
            align-items: center;
            gap: 8px;
            padding: 4px 0;
            font-size: 11px;
            cursor: pointer;
        }

        .value-bar:hover {
            background: \(theme.rowHover);
        }

        .value-bar .bar {
            height: 6px;
            background: \(theme.linkColor);
            border-radius: 3px;
            min-width: 4px;
        }

        .value-bar .text {
            flex: 1;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }

        .value-bar .count {
            color: \(theme.secondaryText);
            font-family: 'SF Mono', Menlo, monospace;
        }

        /* Type badge */
        .type-badge {
            display: inline-flex;
            align-items: center;
            padding: 2px 6px;
            font-size: 10px;
            font-weight: 500;
            border-radius: 4px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        /* Filter Bar */
        .filter-bar {
            display: none;
            align-items: center;
            gap: 8px;
            padding: 8px 12px;
            margin-bottom: 12px;
            background: \(theme.selectedColumn);
            border-radius: 6px;
        }

        .filter-bar.visible {
            display: flex;
        }

        .filter-tag {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            padding: 4px 8px;
            background: \(theme.linkColor);
            color: #ffffff;
            border-radius: 4px;
            font-size: 11px;
        }

        .filter-tag .remove {
            cursor: pointer;
            opacity: 0.8;
        }

        .filter-tag .remove:hover {
            opacity: 1;
        }

        /* Table */
        .table-container {
            overflow-x: auto;
            border: 1px solid \(theme.border);
            border-radius: 8px;
        }

        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 12px;
        }

        th, td {
            padding: 8px 12px;
            text-align: left;
            border-bottom: 1px solid \(theme.border);
            white-space: nowrap;
            max-width: 300px;
            overflow: hidden;
            text-overflow: ellipsis;
            cursor: default;
            position: relative;
        }

        /* Word wrap mode */
        table.word-wrap td {
            white-space: pre-wrap;
            word-break: break-word;
            max-width: 400px;
        }

        /* Expanded cell */
        td.expanded {
            white-space: pre-wrap !important;
            word-break: break-word !important;
            max-width: none !important;
            overflow: visible !important;
            text-overflow: clip !important;
            background: \(theme.selectedColumn) !important;
        }

        /* Truncated indicator */
        td.truncated::after {
            content: '⋯';
            position: absolute;
            right: 4px;
            top: 50%;
            transform: translateY(-50%);
            color: \(theme.linkColor);
            font-size: 10px;
            cursor: pointer;
            opacity: 0;
            transition: opacity 0.15s;
        }

        td.truncated:hover::after {
            opacity: 1;
        }

        td.truncated {
            cursor: pointer;
            padding-right: 20px;
        }

        th {
            background: \(theme.headerBackground);
            font-weight: 600;
            position: sticky;
            top: 0;
            z-index: 10;
            cursor: pointer;
            user-select: none;
        }

        th:hover {
            background: \(theme.buttonHover);
        }

        th.sorted-asc::after {
            content: ' ↑';
            opacity: 0.6;
        }

        th.sorted-desc::after {
            content: ' ↓';
            opacity: 0.6;
        }

        th.selected, td.selected {
            background: \(theme.selectedColumn);
        }

        tr:hover td {
            background: \(theme.rowHover);
        }

        tr.filtered-out {
            display: none;
        }

        tr.highlight td {
            background: \(theme.selectedRow);
        }

        .row-number {
            color: \(theme.secondaryText);
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 11px;
            text-align: right;
            min-width: 40px;
        }

        /* Alternate row colors */
        tbody tr:nth-child(even) td {
            background: \(theme.secondaryBackground);
        }

        tbody tr:nth-child(even):hover td {
            background: \(theme.rowHover);
        }

        /* View containers */
        .view-container {
            display: none;
        }

        .view-container.active {
            display: block;
        }

        /* Markdown view container */
        .markdown-container {
            display: flex;
            flex-direction: column;
            gap: 12px;
        }

        .markdown-toggle {
            display: flex;
            gap: 8px;
            padding-bottom: 8px;
            border-bottom: 1px solid \(theme.border);
        }

        .markdown-toggle .btn.active {
            background: \(theme.linkColor);
            color: #ffffff;
            border-color: \(theme.linkColor);
        }

        /* Markdown source view */
        .markdown-source {
            display: none;
            padding: 16px;
            background: \(theme.secondaryBackground);
            border: 1px solid \(theme.border);
            border-radius: 8px;
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 12px;
            overflow-x: auto;
            white-space: pre;
        }

        .markdown-source.active {
            display: block;
        }

        /* Markdown rendered view */
        .markdown-rendered {
            display: none;
            padding: 16px;
            background: \(theme.secondaryBackground);
            border: 1px solid \(theme.border);
            border-radius: 8px;
            font-size: 13px;
            overflow-x: auto;
        }

        .markdown-rendered.active {
            display: block;
        }

        /* Rendered markdown table styles */
        .markdown-rendered table {
            width: 100%;
            border-collapse: collapse;
            margin: 0;
        }

        .markdown-rendered th,
        .markdown-rendered td {
            padding: 10px 14px;
            text-align: left;
            border: 1px solid \(theme.border);
        }

        .markdown-rendered th {
            background: \(theme.headerBackground);
            font-weight: 600;
        }

        .markdown-rendered tr:nth-child(even) td {
            background: \(theme.background);
        }

        .markdown-rendered tr:nth-child(odd) td {
            background: \(theme.secondaryBackground);
        }

        .markdown-rendered h1, .markdown-rendered h2, .markdown-rendered h3 {
            margin: 0 0 12px 0;
            color: \(theme.text);
        }

        .markdown-rendered p {
            margin: 8px 0;
        }

        .markdown-rendered code {
            background: \(theme.headerBackground);
            padding: 2px 6px;
            border-radius: 4px;
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 12px;
        }

        .markdown-rendered pre {
            background: \(theme.headerBackground);
            padding: 12px;
            border-radius: 6px;
            overflow-x: auto;
        }

        .markdown-rendered pre code {
            background: none;
            padding: 0;
        }

        /* JSON view */
        .json-view {
            padding: 16px;
            background: \(theme.secondaryBackground);
            border: 1px solid \(theme.border);
            border-radius: 8px;
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 12px;
            overflow-x: auto;
            white-space: pre;
        }

        /* TXT (raw) view */
        .txt-view {
            padding: 16px;
            background: \(theme.secondaryBackground);
            border: 1px solid \(theme.border);
            border-radius: 8px;
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 12px;
            overflow-x: auto;
            white-space: pre;
            line-height: 1.6;
        }

        .txt-view .line {
            display: block;
        }

        .txt-view .line-number {
            display: inline-block;
            width: 40px;
            color: \(theme.secondaryText);
            text-align: right;
            margin-right: 16px;
            user-select: none;
        }

        .txt-view .delimiter {
            color: \(theme.linkColor);
        }

        .txt-view .header-line {
            font-weight: 600;
            background: \(theme.headerBackground);
            margin: 0 -16px;
            padding: 0 16px;
        }

        /* More rows indicator */
        .more-rows {
            padding: 12px;
            text-align: center;
            color: \(theme.secondaryText);
            font-size: 12px;
            background: \(theme.secondaryBackground);
            border-top: 1px solid \(theme.border);
        }

        /* Toast notification */
        .toast {
            position: fixed;
            bottom: 20px;
            left: 50%;
            transform: translateX(-50%);
            padding: 10px 20px;
            background: \(theme.text);
            color: \(theme.background);
            border-radius: 8px;
            font-size: 13px;
            opacity: 0;
            transition: opacity 0.3s ease;
            z-index: 1000;
        }

        .toast.visible {
            opacity: 1;
        }

        /* Link styles */
        a {
            color: \(theme.linkColor);
            text-decoration: none;
        }

        a:hover {
            text-decoration: underline;
        }

        /* Close button for stats panel */
        .close-btn {
            position: absolute;
            top: 8px;
            right: 8px;
            background: none;
            border: none;
            font-size: 18px;
            cursor: pointer;
            color: \(theme.secondaryText);
            padding: 4px 8px;
        }

        .close-btn:hover {
            color: \(theme.text);
        }

        /* Empty cell indicator */
        .empty-cell {
            color: \(theme.secondaryText);
            font-style: italic;
        }
        """
    }

    // MARK: - Header

    private static func generateHeader(
        fileName: String,
        filePath: String?,
        data: CSVData,
        fileSize: Int64?,
        modificationDate: Date?,
        githubURL: String?,
        hasMoreRows: Bool,
        maxDisplayRows: Int
    ) -> String {
        let delimiterName = data.delimiter == "\t" ? "Tab-separated" : (data.delimiter == ";" ? "Semicolon-separated" : "Comma-separated")
        let rowCountStr = hasMoreRows ? "\(data.totalRows.formatted()) rows (showing \(maxDisplayRows.formatted()))" : "\(data.totalRows.formatted()) rows"

        var metaItems: [String] = [
            "<span>📊 \(rowCountStr) × \(data.totalColumns) columns</span>",
            "<span>📄 \(delimiterName)</span>"
        ]

        if let size = fileSize {
            metaItems.append("<span>💾 \(formatFileSize(size))</span>")
        }

        if let date = modificationDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            metaItems.append("<span>📅 \(formatter.string(from: date))</span>")
        }

        var actionsHTML = """
        <button class="btn" onclick="copyTable()">📋 Copy Table</button>
        """

        if let github = githubURL {
            actionsHTML += """
            <a class="btn" href="\(github)" target="_blank">🔗 GitHub</a>
            """
        }

        if filePath != nil {
            actionsHTML += """
            <button class="btn" onclick="copyPath()">📁 Copy Path</button>
            """
        }

        return """
        <header class="header">
            <h1>
                <span class="icon">📊</span>
                \(escapeHTML(fileName))
            </h1>
            <div class="header-meta">
                \(metaItems.joined(separator: "\n                "))
            </div>
            <div class="header-actions">
                \(actionsHTML)
            </div>
        </header>
        <input type="hidden" id="filePath" value="\(escapeHTML(filePath ?? ""))">
        """
    }

    // MARK: - Toolbar

    private static func generateToolbar(hasHeaders: Bool) -> String {
        let checkedAttr = hasHeaders ? "checked" : ""
        return """
        <div class="toolbar">
            <div class="toolbar-left">
                <div class="btn-group">
                    <button class="btn active" data-view="table" onclick="switchView('table')">Table</button>
                    <button class="btn" data-view="markdown" onclick="switchView('markdown')">Markdown</button>
                    <button class="btn" data-view="json" onclick="switchView('json')">JSON</button>
                    <button class="btn" data-view="txt" onclick="switchView('txt')">TXT</button>
                </div>
                <label class="header-toggle" title="Use first row as column headers">
                    <input type="checkbox" id="headerToggle" \(checkedAttr) onchange="toggleHeaderRow(this.checked)">
                    <span>First row is headers</span>
                </label>
            </div>
            <div class="toolbar-right">
                <div class="search-box">
                    <span>🔍</span>
                    <input type="text" id="searchInput" placeholder="Search... (⌘F)" oninput="handleSearch(this.value)">
                </div>
                <button class="btn" id="wrapBtn" onclick="toggleWordWrap()">↩️ Wrap</button>
                <button class="btn" id="expandAllBtn" onclick="toggleExpandAll()">⬇️ Expand</button>
                <button class="btn" id="statsBtn" onclick="toggleStatsPanel()">📈 Stats</button>
            </div>
        </div>
        """
    }

    // MARK: - Stats Panel

    private static func generateStatsPanel(stats: [String: ColumnStats], data: CSVData) -> String {
        // Build column options for dropdown
        let columnOptions = data.headers.enumerated().map { i, header in
            "<option value=\"\(i)\">\(escapeHTML(header))</option>"
        }.joined(separator: "\n")

        return """
        <div class="stats-panel" id="statsPanel">
            <button class="close-btn" onclick="toggleStatsPanel()">×</button>
            <h3>Column Statistics</h3>
            <select id="statsColumnSelect" onchange="showColumnStats(this.value)" style="width: 100%; padding: 8px; margin-bottom: 16px; border-radius: 4px; border: 1px solid var(--border);">
                <option value="">Select a column...</option>
                \(columnOptions)
            </select>
            <div id="statsContent">
                <p style="color: var(--secondary-text); font-size: 12px;">Click a column header or select from dropdown to view statistics.</p>
            </div>
        </div>
        """
    }

    // MARK: - Filter Bar

    private static func generateFilterBar() -> String {
        return """
        <div class="filter-bar" id="filterBar">
            <span>🔽 Filters:</span>
            <div id="filterTags"></div>
            <button class="btn" onclick="clearAllFilters()">Clear All</button>
        </div>
        """
    }

    // MARK: - Table View

    private static func generateTableView(data: CSVData, displayRows: [[String]], stats: [String: ColumnStats]) -> String {
        // Generate header row with type badges
        let headerCells = data.headers.enumerated().map { i, header -> String in
            let stat = stats[header]
            let typeBadge = stat.map { s in
                "<span class=\"type-badge\" style=\"background: \(s.type.badgeColor); color: white; margin-left: 6px;\">\(s.type.rawValue)</span>"
            } ?? ""

            return "<th data-col=\"\(i)\" onclick=\"selectColumn(\(i))\">\(escapeHTML(header))\(typeBadge)</th>"
        }.joined(separator: "\n            ")

        // Generate data rows
        let dataRows = displayRows.enumerated().map { rowIdx, row -> String in
            let cells = data.headers.indices.map { colIdx -> String in
                let value = colIdx < row.count ? row[colIdx] : ""
                let displayValue = value.isEmpty ? "<span class=\"empty-cell\">—</span>" : escapeHTML(value)
                return "<td data-col=\"\(colIdx)\" data-value=\"\(escapeHTML(value))\">\(displayValue)</td>"
            }.joined(separator: "\n                ")

            return """
                    <tr data-row=\"\(rowIdx)\">
                        <td class=\"row-number\">\(rowIdx + 1)</td>
                        \(cells)
                    </tr>
            """
        }.joined(separator: "\n")

        let moreRowsHTML = displayRows.count < data.totalRows ? """
        <div class="more-rows">
            Showing \(displayRows.count.formatted()) of \(data.totalRows.formatted()) rows. Large files are truncated for performance.
        </div>
        """ : ""

        return """
        <div class="view-container active" id="tableView">
            <div class="table-container">
                <table id="dataTable">
                    <thead>
                        <tr>
                            <th class="row-number">#</th>
                            \(headerCells)
                        </tr>
                    </thead>
                    <tbody>
        \(dataRows)
                    </tbody>
                </table>
            </div>
            \(moreRowsHTML)
        </div>
        """
    }

    // MARK: - Markdown View

    private static func generateMarkdownView(data: CSVData, displayRows: [[String]]) -> String {
        let markdown = data.toMarkdown(maxRows: min(displayRows.count, 500))

        // Escape the markdown for embedding in a script tag (as JSON string)
        let markdownForJS = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")

        return """
        <div class="view-container" id="markdownView">
            <div class="markdown-container">
                <div class="markdown-toggle">
                    <button class="btn active" id="mdRenderedBtn" onclick="switchMarkdownMode('rendered')">📖 Rendered</button>
                    <button class="btn" id="mdSourceBtn" onclick="switchMarkdownMode('source')">📝 Source</button>
                    <button class="btn" onclick="copyMarkdown()">📋 Copy</button>
                </div>
                <div class="markdown-rendered active" id="markdownRendered">
                    <!-- Rendered content inserted by JavaScript -->
                </div>
                <div class="markdown-source" id="markdownSource">\(escapeHTML(markdown))</div>
            </div>
        </div>
        <script id="markdownData" type="application/json">"\(markdownForJS)"</script>
        """
    }

    // MARK: - JSON View

    private static func generateJSONView(data: CSVData, displayRows: [[String]]) -> String {
        let json = data.toJSON(maxRows: min(displayRows.count, 500))

        return """
        <div class="view-container" id="jsonView">
            <div class="json-view" id="jsonContent">\(escapeHTML(json))</div>
        </div>
        """
    }

    // MARK: - TXT (Raw) View

    private static func generateTXTView(rawContent: String?, data: CSVData) -> String {
        // If no raw content, reconstruct from data
        let content: String
        if let raw = rawContent {
            content = raw
        } else {
            // Reconstruct raw CSV from parsed data
            let delimiterStr = String(data.delimiter)
            var lines: [String] = []
            lines.append(data.headers.map { escapeCSVField($0, delimiter: data.delimiter) }.joined(separator: delimiterStr))
            for row in data.rows.prefix(1000) {
                lines.append(row.map { escapeCSVField($0, delimiter: data.delimiter) }.joined(separator: delimiterStr))
            }
            content = lines.joined(separator: "\n")
        }

        // Generate highlighted raw content with line numbers
        let lines = content.components(separatedBy: .newlines)
        let delimiterChar = data.delimiter
        let delimiterEscaped = delimiterChar == "\t" ? "\\t" : escapeHTML(String(delimiterChar))

        var htmlLines: [String] = []
        for (index, line) in lines.prefix(1000).enumerated() {
            let lineNum = index + 1
            let isHeader = index == 0
            let lineClass = isHeader ? "line header-line" : "line"

            // Highlight delimiters
            let highlightedLine = escapeHTML(line).replacingOccurrences(
                of: escapeHTML(String(delimiterChar)),
                with: "<span class=\"delimiter\">\(delimiterEscaped)</span>"
            )

            htmlLines.append("<span class=\"\(lineClass)\"><span class=\"line-number\">\(lineNum)</span>\(highlightedLine)</span>")
        }

        let moreLines = lines.count > 1000 ? "\n<span class=\"line\" style=\"color: var(--secondary-text);\">... (\(lines.count - 1000) more lines)</span>" : ""

        return """
        <div class="view-container" id="txtView">
            <div class="txt-view" id="txtContent">\(htmlLines.joined(separator: "\n"))\(moreLines)</div>
        </div>
        """
    }

    private static func escapeCSVField(_ field: String, delimiter: Character) -> String {
        let needsQuotes = field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r")
        if needsQuotes {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    // MARK: - JavaScript

    private static func generateJavaScript(data: CSVData, displayRows: [[String]], stats: [String: ColumnStats]) -> String {
        // Serialize stats to JSON for JavaScript
        let statsJSON = serializeStats(stats, headers: data.headers)

        // Serialize all rows for header toggle functionality
        let allRowsJSON = serializeRows(displayRows)
        let originalHeadersJSON = serializeArray(data.headers)
        let hadHeadersInitially = data.hasHeaders

        return """
        // Data and state
        const columnStats = \(statsJSON);
        let headers = \(serializeArray(data.headers));
        const originalHeaders = \(originalHeadersJSON);
        const allDataRows = \(allRowsJSON);
        let hasHeaders = \(hadHeadersInitially ? "true" : "false");
        let selectedColumn = -1;
        let sortColumn = -1;
        let sortDirection = 'none';
        let activeFilters = {};

        // View switching
        function switchView(view) {
            document.querySelectorAll('.view-container').forEach(el => el.classList.remove('active'));
            document.querySelectorAll('.btn-group .btn').forEach(el => el.classList.remove('active'));

            document.getElementById(view + 'View').classList.add('active');
            document.querySelector('.btn[data-view="' + view + '"]').classList.add('active');
        }

        // Toggle first row as headers
        function toggleHeaderRow(useFirstRowAsHeaders) {
            hasHeaders = useFirstRowAsHeaders;

            let currentHeaders, currentRows;

            if (useFirstRowAsHeaders) {
                currentHeaders = originalHeaders;
                currentRows = allDataRows;
            } else {
                // Generate Column 1, Column 2, etc. headers
                const colCount = originalHeaders.length;
                currentHeaders = [];
                for (let i = 1; i <= colCount; i++) {
                    currentHeaders.push('Column ' + i);
                }
                // Include the original headers as the first data row
                currentRows = [originalHeaders].concat(allDataRows);
            }

            headers = currentHeaders;

            // Update table headers using DOM methods
            const thead = document.querySelector('#tableView thead tr');
            if (thead) {
                thead.replaceChildren();
                currentHeaders.forEach((h, i) => {
                    const th = document.createElement('th');
                    th.dataset.col = i;
                    th.onclick = () => selectColumn(i);
                    th.textContent = h;
                    thead.appendChild(th);
                });
            }

            // Update table body using DOM methods
            const tbody = document.querySelector('#tableView tbody');
            if (tbody) {
                tbody.replaceChildren();
                currentRows.forEach((row, ri) => {
                    const tr = document.createElement('tr');
                    currentHeaders.forEach((_, ci) => {
                        const td = document.createElement('td');
                        td.dataset.col = ci;
                        td.textContent = row[ci] || '';
                        tr.appendChild(td);
                    });
                    tbody.appendChild(tr);
                });
            }

            // Update JSON view
            const jsonView = document.getElementById('jsonContent');
            if (jsonView) {
                const jsonData = currentRows.map(row => {
                    const obj = {};
                    currentHeaders.forEach((h, i) => {
                        obj[h] = row[i] || '';
                    });
                    return obj;
                });
                jsonView.textContent = JSON.stringify(jsonData, null, 2);
            }

            // Update markdown view
            updateMarkdownView(currentHeaders, currentRows);

            // Update stats dropdown using DOM methods
            const statsSelect = document.getElementById('statsColumnSelect');
            if (statsSelect) {
                statsSelect.replaceChildren();
                const defaultOpt = document.createElement('option');
                defaultOpt.value = '';
                defaultOpt.textContent = 'Select a column...';
                statsSelect.appendChild(defaultOpt);
                currentHeaders.forEach((h, i) => {
                    const opt = document.createElement('option');
                    opt.value = i;
                    opt.textContent = h;
                    statsSelect.appendChild(opt);
                });
            }
        }

        function updateMarkdownView(hdrs, rows) {
            const mdContainer = document.getElementById('markdownRendered');
            const mdSource = document.getElementById('markdownSource');
            if (!mdContainer || !mdSource) return;

            // Build markdown table
            let md = '| ' + hdrs.join(' | ') + ' |\\n';
            md += '| ' + hdrs.map(() => '---').join(' | ') + ' |\\n';
            rows.slice(0, 500).forEach(row => {
                md += '| ' + hdrs.map((_, i) => row[i] || '').join(' | ') + ' |\\n';
            });

            mdSource.textContent = md;
            if (typeof marked !== 'undefined') {
                mdContainer.replaceChildren();
                const div = document.createElement('div');
                // Use marked's safe parsing
                div.innerHTML = marked.parse(md, { sanitize: false, headerIds: false });
                mdContainer.appendChild(div);
            }
        }

        // Column selection
        function selectColumn(colIndex) {
            // Remove previous selection
            document.querySelectorAll('th.selected, td.selected').forEach(el => el.classList.remove('selected'));

            if (selectedColumn === colIndex) {
                selectedColumn = -1;
                document.getElementById('statsPanel').classList.remove('visible');
                document.getElementById('statsColumnSelect').value = '';
                return;
            }

            selectedColumn = colIndex;

            // Highlight column
            document.querySelectorAll('[data-col="' + colIndex + '"]').forEach(el => el.classList.add('selected'));

            // Show stats panel
            showColumnStats(colIndex);
            document.getElementById('statsPanel').classList.add('visible');
            document.getElementById('statsColumnSelect').value = colIndex;
        }

        // Show column statistics - builds DOM safely using createElement/textContent
        function showColumnStats(colIndex) {
            const container = document.getElementById('statsContent');
            container.replaceChildren(); // Clear safely

            if (colIndex === '' || colIndex === null) {
                const p = document.createElement('p');
                p.style.cssText = 'color: var(--secondary-text); font-size: 12px;';
                p.textContent = 'Select a column to view statistics.';
                container.appendChild(p);
                return;
            }

            const idx = parseInt(colIndex);
            const header = headers[idx];
            const stat = columnStats[header];

            if (!stat) {
                const p = document.createElement('p');
                p.textContent = 'No statistics available.';
                container.appendChild(p);
                return;
            }

            // Build stats rows using DOM methods
            function addStatsRow(label, value, isHtml) {
                const row = document.createElement('div');
                row.className = 'stats-row';

                const labelSpan = document.createElement('span');
                labelSpan.className = 'label';
                labelSpan.textContent = label;

                const valueSpan = document.createElement('span');
                valueSpan.className = 'value';
                if (isHtml) {
                    valueSpan.insertAdjacentHTML('beforeend', value);
                } else {
                    valueSpan.textContent = value;
                }

                row.appendChild(labelSpan);
                row.appendChild(valueSpan);
                container.appendChild(row);
            }

            // Type badge (safe - using pre-sanitized color)
            const typeBadgeHtml = '<span class="type-badge" style="background: ' + stat.badgeColor + '; color: white;">' + stat.type + '</span>';
            addStatsRow('Type', typeBadgeHtml, true);
            addStatsRow('Count', stat.count.toLocaleString(), false);
            addStatsRow('Non-empty', stat.nonEmptyCount.toLocaleString() + ' (' + stat.fillRate.toFixed(1) + '%)', false);
            addStatsRow('Distinct', stat.distinctCount.toLocaleString(), false);

            if (stat.min !== null) addStatsRow('Min', stat.min, false);
            if (stat.max !== null) addStatsRow('Max', stat.max, false);
            if (stat.sum !== null) addStatsRow('Sum', stat.sum.toLocaleString(), false);
            if (stat.average !== null) addStatsRow('Average', stat.average.toFixed(2), false);

            // Top values
            if (stat.topValues && stat.topValues.length > 0) {
                const topDiv = document.createElement('div');
                topDiv.className = 'top-values';

                const h4 = document.createElement('h4');
                h4.textContent = 'Top Values';
                topDiv.appendChild(h4);

                const maxCount = stat.topValues[0].count;
                stat.topValues.slice(0, 10).forEach(v => {
                    const pct = (v.count / maxCount * 100).toFixed(0);
                    const displayValue = v.value === '' ? '(empty)' : v.value;

                    const bar = document.createElement('div');
                    bar.className = 'value-bar';
                    bar.onclick = () => filterByValue(idx, v.value);

                    const barInner = document.createElement('div');
                    barInner.className = 'bar';
                    barInner.style.width = pct + 'px';

                    const textSpan = document.createElement('span');
                    textSpan.className = 'text';
                    textSpan.textContent = displayValue;

                    const countSpan = document.createElement('span');
                    countSpan.className = 'count';
                    countSpan.textContent = v.count.toLocaleString();

                    bar.appendChild(barInner);
                    bar.appendChild(textSpan);
                    bar.appendChild(countSpan);
                    topDiv.appendChild(bar);
                });

                container.appendChild(topDiv);
            }
        }

        function toggleStatsPanel() {
            document.getElementById('statsPanel').classList.toggle('visible');
        }

        // Sorting
        function sortByColumn(colIndex) {
            const table = document.getElementById('dataTable');
            const tbody = table.querySelector('tbody');
            const rows = Array.from(tbody.querySelectorAll('tr'));

            // Determine sort direction
            if (sortColumn === colIndex) {
                sortDirection = sortDirection === 'asc' ? 'desc' : (sortDirection === 'desc' ? 'none' : 'asc');
            } else {
                sortColumn = colIndex;
                sortDirection = 'asc';
            }

            // Update header classes
            document.querySelectorAll('th').forEach(th => {
                th.classList.remove('sorted-asc', 'sorted-desc');
            });

            if (sortDirection !== 'none') {
                document.querySelector('th[data-col="' + colIndex + '"]').classList.add('sorted-' + sortDirection);
            }

            // Sort rows
            if (sortDirection === 'none') {
                // Restore original order by row number
                rows.sort((a, b) => parseInt(a.dataset.row) - parseInt(b.dataset.row));
            } else {
                rows.sort((a, b) => {
                    const aVal = a.querySelector('td[data-col="' + colIndex + '"]').dataset.value;
                    const bVal = b.querySelector('td[data-col="' + colIndex + '"]').dataset.value;

                    // Try numeric comparison
                    const aNum = parseFloat(aVal.replace(/,/g, ''));
                    const bNum = parseFloat(bVal.replace(/,/g, ''));

                    let result;
                    if (!isNaN(aNum) && !isNaN(bNum)) {
                        result = aNum - bNum;
                    } else {
                        result = aVal.localeCompare(bVal);
                    }

                    return sortDirection === 'desc' ? -result : result;
                });
            }

            rows.forEach(row => tbody.appendChild(row));
        }

        // Add click handler for sorting (double-click header)
        document.querySelectorAll('th[data-col]').forEach(th => {
            th.addEventListener('dblclick', () => sortByColumn(parseInt(th.dataset.col)));
        });

        // Filtering
        function filterByValue(colIndex, value) {
            activeFilters[colIndex] = value;
            applyFilters();
            updateFilterBar();
        }

        function removeFilter(colIndex) {
            delete activeFilters[colIndex];
            applyFilters();
            updateFilterBar();
        }

        function clearAllFilters() {
            activeFilters = {};
            applyFilters();
            updateFilterBar();
        }

        function applyFilters() {
            const rows = document.querySelectorAll('#dataTable tbody tr');

            rows.forEach(row => {
                let visible = true;

                for (const [colIndex, value] of Object.entries(activeFilters)) {
                    const cell = row.querySelector('td[data-col="' + colIndex + '"]');
                    if (cell && cell.dataset.value !== value) {
                        visible = false;
                        break;
                    }
                }

                row.classList.toggle('filtered-out', !visible);
            });
        }

        function updateFilterBar() {
            const filterBar = document.getElementById('filterBar');
            const filterTags = document.getElementById('filterTags');
            filterTags.replaceChildren(); // Clear safely

            if (Object.keys(activeFilters).length === 0) {
                filterBar.classList.remove('visible');
                return;
            }

            filterBar.classList.add('visible');

            for (const [colIndex, value] of Object.entries(activeFilters)) {
                const header = headers[colIndex];
                const displayValue = value === '' ? '(empty)' : value;

                const tag = document.createElement('span');
                tag.className = 'filter-tag';

                const tagText = document.createTextNode(header + ': ' + displayValue + ' ');
                tag.appendChild(tagText);

                const removeBtn = document.createElement('span');
                removeBtn.className = 'remove';
                removeBtn.textContent = '×';
                removeBtn.onclick = () => removeFilter(colIndex);
                tag.appendChild(removeBtn);

                filterTags.appendChild(tag);
            }
        }

        // Search
        function handleSearch(query) {
            const rows = document.querySelectorAll('#dataTable tbody tr');
            const lowerQuery = query.toLowerCase();

            rows.forEach(row => {
                if (!query) {
                    row.classList.remove('filtered-out', 'highlight');
                    return;
                }

                const cells = row.querySelectorAll('td[data-value]');
                let match = false;

                cells.forEach(cell => {
                    const value = cell.dataset.value.toLowerCase();
                    if (value.includes(lowerQuery)) {
                        match = true;
                    }
                });

                row.classList.toggle('filtered-out', !match);
                row.classList.toggle('highlight', match && query.length > 0);
            });
        }

        // Word wrap toggle
        let wordWrapEnabled = false;
        function toggleWordWrap() {
            wordWrapEnabled = !wordWrapEnabled;
            const table = document.getElementById('dataTable');
            const btn = document.getElementById('wrapBtn');

            table.classList.toggle('word-wrap', wordWrapEnabled);
            btn.classList.toggle('active', wordWrapEnabled);

            if (wordWrapEnabled) {
                showToast('Word wrap enabled');
            } else {
                showToast('Word wrap disabled');
            }
        }

        // Expand/collapse all cells
        let allExpanded = false;
        function toggleExpandAll() {
            allExpanded = !allExpanded;
            const cells = document.querySelectorAll('#dataTable td[data-col]');
            const btn = document.getElementById('expandAllBtn');

            cells.forEach(cell => {
                if (allExpanded) {
                    cell.classList.add('expanded');
                } else {
                    cell.classList.remove('expanded');
                }
            });

            btn.classList.toggle('active', allExpanded);
            btn.textContent = allExpanded ? '⬆️ Collapse' : '⬇️ Expand';

            if (allExpanded) {
                showToast('All cells expanded');
            } else {
                showToast('All cells collapsed');
            }
        }

        // Toggle individual cell expansion
        function toggleCellExpand(cell) {
            cell.classList.toggle('expanded');
        }

        // Mark truncated cells and add click handler
        function markTruncatedCells() {
            const cells = document.querySelectorAll('#dataTable td[data-col]');
            cells.forEach(cell => {
                // Check if content is truncated
                if (cell.scrollWidth > cell.clientWidth) {
                    cell.classList.add('truncated');
                    cell.addEventListener('click', function(e) {
                        // Don't toggle if clicking to select column
                        if (!e.shiftKey) {
                            toggleCellExpand(this);
                        }
                    });
                }
            });
        }

        // Run after DOM is ready
        document.addEventListener('DOMContentLoaded', markTruncatedCells);
        // Also run after a slight delay for dynamic content
        setTimeout(markTruncatedCells, 100);

        // Keyboard shortcuts
        document.addEventListener('keydown', (e) => {
            // Cmd+F for search
            if ((e.metaKey || e.ctrlKey) && e.key === 'f') {
                e.preventDefault();
                document.getElementById('searchInput').focus();
            }

            // Escape to clear search/filters
            if (e.key === 'Escape') {
                document.getElementById('searchInput').value = '';
                handleSearch('');
                clearAllFilters();
            }
        });

        // Copy functions
        function copyTable() {
            const table = document.getElementById('dataTable');
            const rows = table.querySelectorAll('tr:not(.filtered-out)');

            let text = '';
            rows.forEach((row, i) => {
                const cells = i === 0 ?
                    row.querySelectorAll('th[data-col]') :
                    row.querySelectorAll('td[data-col]');
                const values = Array.from(cells).map(cell => cell.dataset.value || cell.textContent);
                text += values.join('\\t') + '\\n';
            });

            navigator.clipboard.writeText(text).then(() => showToast('Table copied to clipboard'));
        }

        function copyPath() {
            const path = document.getElementById('filePath').value;
            navigator.clipboard.writeText(path).then(() => showToast('Path copied to clipboard'));
        }

        function showToast(message) {
            const toast = document.createElement('div');
            toast.className = 'toast';
            toast.textContent = message;
            document.body.appendChild(toast);

            requestAnimationFrame(() => {
                toast.classList.add('visible');
                setTimeout(() => {
                    toast.classList.remove('visible');
                    setTimeout(() => toast.remove(), 300);
                }, 2000);
            });
        }

        // Markdown mode switching
        function switchMarkdownMode(mode) {
            const renderedEl = document.getElementById('markdownRendered');
            const sourceEl = document.getElementById('markdownSource');
            const renderedBtn = document.getElementById('mdRenderedBtn');
            const sourceBtn = document.getElementById('mdSourceBtn');

            if (mode === 'rendered') {
                renderedEl.classList.add('active');
                sourceEl.classList.remove('active');
                renderedBtn.classList.add('active');
                sourceBtn.classList.remove('active');
            } else {
                renderedEl.classList.remove('active');
                sourceEl.classList.add('active');
                renderedBtn.classList.remove('active');
                sourceBtn.classList.add('active');
            }
        }

        function copyMarkdown() {
            const source = document.getElementById('markdownSource').textContent;
            navigator.clipboard.writeText(source).then(() => showToast('Markdown copied to clipboard'));
        }

        // Initialize rendered markdown on page load
        document.addEventListener('DOMContentLoaded', function() {
            const sourceEl = document.getElementById('markdownSource');
            const renderedEl = document.getElementById('markdownRendered');
            if (sourceEl && renderedEl) {
                const markdown = sourceEl.textContent;
                renderedEl.innerHTML = renderMarkdownTable(markdown);
            }
        });
        """
    }

    // MARK: - Helpers

    private static func escapeHTML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private static func isDarkModeEnabled() -> Bool {
        // Check system appearance
        if let appearance = NSAppearance.current?.name {
            return appearance == .darkAqua || appearance == .vibrantDark ||
                   appearance == .accessibilityHighContrastDarkAqua ||
                   appearance == .accessibilityHighContrastVibrantDark
        }
        return false
    }

    private static func serializeStats(_ stats: [String: ColumnStats], headers: [String]) -> String {
        var obj: [String: Any] = [:]

        for header in headers {
            if let stat = stats[header] {
                var statObj: [String: Any] = [
                    "type": stat.type.rawValue,
                    "badgeColor": stat.type.badgeColor,
                    "count": stat.count,
                    "nonEmptyCount": stat.nonEmptyCount,
                    "distinctCount": stat.distinctCount,
                    "nullCount": stat.nullCount,
                    "fillRate": stat.fillRate
                ]

                if let min = stat.min { statObj["min"] = min }
                if let max = stat.max { statObj["max"] = max }
                if let sum = stat.sum { statObj["sum"] = sum }
                if let avg = stat.average { statObj["average"] = avg }

                let topValues = stat.topValues.prefix(20).map { ["value": $0.value, "count": $0.count] }
                statObj["topValues"] = topValues

                obj[header] = statObj
            }
        }

        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }

        return json
    }

    private static func serializeArray(_ array: [String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: array),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }

    private static func serializeRows(_ rows: [[String]]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: rows),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}
