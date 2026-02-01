# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

QLQuickCSV is a macOS Quick Look extension that provides interactive, table-based previews for CSV and TSV files. Unlike basic text viewers, it renders data as proper HTML tables with column analysis, filtering, sorting, and export capabilities.

**Philosophy**: CSV files are data, not text. View them like a spreadsheet, not a code file.

**Key Features:**
- Interactive HTML table with sticky headers
- Column type auto-detection (text, integer, decimal, date, boolean)
- Column statistics panel (count, min, max, sum, avg, distinct values)
- Sort by clicking column headers (double-click)
- Filter by clicking on values in the stats panel
- Multiple view modes: Table, Markdown, JSON
- Search across all data (Cmd+F)
- Copy as CSV, Markdown, JSON, or SQL
- Dark/light mode support
- GitHub URL integration

## Build Commands

```bash
# Prerequisites
brew install xcodegen

# Regenerate Xcode project from project.yml
xcodegen generate

# Build debug
xcodebuild -project QLQuickCSV.xcodeproj -scheme QLQuickCSV -configuration Debug build

# Build release
xcodebuild -project QLQuickCSV.xcodeproj -scheme QLQuickCSV -configuration Release build

# Build and create distribution DMG/ZIP
./build-release.sh [version]

# Clean build
xcodebuild -project QLQuickCSV.xcodeproj -scheme QLQuickCSV clean
```

## Testing Quick Look

```bash
# Install to Applications
cp -R ~/Library/Developer/Xcode/DerivedData/QLQuickCSV-*/Build/Products/Release/QLQuickCSV.app /Applications/

# Open host app to register extension
open /Applications/QLQuickCSV.app

# Enable in System Settings → Privacy & Security → Extensions → Quick Look

# Test preview
qlmanage -p /path/to/file.csv

# Reset Quick Look cache (when extension not loading)
qlmanage -r cache && qlmanage -r

# Check extension status
pluginkit -m -i com.qlcsv.QLQuickCSV.CSVQLExtension
```

## Architecture

```
├── QLQuickCSV/                    # Host SwiftUI app
│   ├── QLQuickCSVApp.swift        # App entry point + menu commands
│   ├── ContentView.swift          # Settings/About UI
│   ├── CSVDocument.swift          # Document model (FileDocument)
│   └── CSVDocumentView.swift      # WebView-based table viewer
├── CSVQLExtension/                # Quick Look extension (.appex)
│   ├── PreviewViewController.swift  # QLPreviewingController implementation
│   └── Base.lproj/                # NIB for legacy view-based preview
├── Shared/                        # Shared between app and extension
│   ├── CSVParser.swift            # RFC 4180 CSV parsing
│   ├── CSVAnalyzer.swift          # Type detection, statistics
│   ├── HTMLGenerator.swift        # HTML table generation with JS
│   ├── Settings.swift             # Cross-process settings (CFPreferences)
│   └── GitHelper.swift            # Git repo detection
└── project.yml                    # XcodeGen specification
```

**Data Flow:**
1. Quick Look calls `providePreview(for:)` in PreviewViewController
2. PreviewViewController uses CSVParser to parse the file
3. CSVAnalyzer calculates column statistics
4. HTMLGenerator creates interactive HTML with embedded JS
5. Returns `QLPreviewReply` with HTML data

**Settings Sharing:** The host app writes to CFPreferences (`com.qlcsv.shared`). The extension reads from the host app's sandboxed plist file at `~/Library/Containers/com.qlcsv.QLQuickCSV/Data/Library/Preferences/`.

## Key Implementation Details

**RFC 4180 CSV Parsing:** The CSVParser handles:
- Quoted fields with embedded delimiters
- Quote escaping (doubled quotes `""`)
- Newlines within quoted fields
- Multiple delimiter types (comma, tab, semicolon, pipe)
- Auto-detection of delimiter and header row

**Column Type Detection:** CSVAnalyzer detects:
- `integer`: Whole numbers (including negative)
- `decimal`: Floating-point numbers
- `date`: ISO 8601 and common date formats
- `boolean`: true/false, yes/no, 1/0
- `text`: Everything else
- `mixed`: Columns with multiple types

**Interactive Features (JavaScript):**
- Single-click header: Select column, show stats panel
- Double-click header: Sort ascending/descending
- Click value in stats: Filter rows by that value
- Cmd+F: Focus search box
- Escape: Clear search and filters

## Bundle Identifiers

- Host app: `com.qlcsv.QLQuickCSV`
- Extension: `com.qlcsv.QLQuickCSV.CSVQLExtension`
- Settings domain: `com.qlcsv.shared`

## File Support

| Extension | UTI | Description |
|-----------|-----|-------------|
| .csv | public.comma-separated-values-text | Comma-separated |
| .tsv | public.tab-separated-values-text | Tab-separated |

## Troubleshooting

**Extension not loading (shows plain text instead of table):**
1. Check for stale registrations: `lsregister -dump | grep QLQuickCSV`
2. Full reset: `pluginkit -e ignore -i com.qlcsv.QLQuickCSV.CSVQLExtension`
3. Kill quicklookd: `killall quicklookd && qlmanage -r cache && qlmanage -r`
4. Reinstall to /Applications and re-register

**CSV not parsing correctly:**
- Check file encoding (UTF-8 expected, but UTF-16 and Latin-1 also supported)
- Verify delimiter (auto-detection may fail on edge cases)
- Try opening in host app to see full error details

**Large files slow:**
- Adjust `maxDisplayRows` in Settings (default: 1000)
- Large files are automatically truncated for performance
