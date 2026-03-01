# QLQuickCSV — Quick Look Extension for CSV Data

A macOS Quick Look extension that turns CSV files into interactive data tables with type detection, statistics, sorting, filtering, and multi-format export — because CSV files are data, not text.

```
  BEFORE (default macOS)              AFTER (QLQuickCSV)
  ┌─────────────────────────┐        ┌──────────────────────────────────┐
  │ id,name,email,amount    │        │ ┌ Table (sorted by amount ▼) ──┐ │
  │ 1,Alice,alice@co,1250   │        │ │ id▾  name▾  email▾ amount▾  │ │
  │ 2,Bob,bob@co,3400       │        │ │ INT  TEXT   TEXT   DECIMAL  │ │
  │ ...                     │        │ ├────────────────────────────┤ │
  │ Raw text. No types,     │        │ │  4   Dave   dave   5,200   │ │
  │ no sorting, no totals.  │        │ │  2   Bob    bob    3,400   │ │
  └─────────────────────────┘        │ └────────────────────────────┘ │
                                     └──────────────────────────────────┘
```

## Features

### Interactive Table
- Sticky headers with click-to-sort columns
- Color-coded type badges: INT, DECIMAL, DATE, BOOL, TEXT, MIXED
- Filter by clicking any cell value
- Cell expand/collapse for long content
- Line numbers and search (Cmd+F)

### Smart Parsing
- **RFC 4180 compliant** state machine parser (handles quoted fields, escaped quotes, embedded newlines)
- **Auto-detect delimiter**: comma, tab, semicolon, or pipe — scored by consistency across first 10 lines
- **Header auto-detection**: unique values, common patterns, no-numbers heuristic
- **4 encoding fallbacks**: UTF-8 → UTF-16 → CP1252 → ISO Latin-1

### Data Analysis
- Column statistics: count, distinct values, nulls, min/max/average
- Top value frequency tracking
- 12 date format patterns recognized
- "Mixed" type signals data quality issues worth investigating

### View Modes
- **Table**: Interactive sortable/filterable table
- **Markdown**: Copy-paste ready for documentation
- **JSON**: Array-of-objects for API use
- **Raw**: Original file content

### Companion App
- Tabbed document windows with Open Files Navigator
- Session persistence across app launches
- Zoom controls and word wrap toggle
- Editor integration (VS Code, Sublime Text)
- Git repository detection with GitHub blob/blame URLs

## Architecture

```
CSVQLExtension/              Quick Look extension (99 lines)
QLQuickCSV/                  SwiftUI host app (~1,200 lines)
Shared/                      Data engine (both targets)
├── CSVParser.swift            RFC 4180 state machine (453 ln)
├── CSVAnalyzer.swift          Type detection + stats (374 ln)
├── HTMLGenerator.swift        Table + JS + CSS (1,817 ln)
├── Settings.swift             CFPreferences cross-process
└── GitHelper.swift            .git/ direct reading
```

## Installation

### From DMG
1. Download `QLQuickCSV.dmg` from Releases
2. Drag `QLQuickCSV.app` to Applications
3. Open the app (registers the extension)
4. Enable in **System Settings → Privacy & Security → Extensions → Quick Look**
5. Press Space on any `.csv` or `.tsv` file in Finder

### Building from Source
```bash
brew install xcodegen
git clone https://github.com/soe219/quicklook-csv.git
cd quicklook-csv
xcodegen generate
xcodebuild -project QLQuickCSV.xcodeproj -scheme QLQuickCSV -configuration Release build
```

## By The Numbers

| Metric | Value |
|--------|-------|
| Swift source | 5,455 lines |
| Commits | 11 |
| Date formats | 12 recognized |
| Encoding fallbacks | 4 |
| Delimiter types | 4 auto-detected |
| View modes | 4 |
| Color themes | 4 |
| Distribution | QLQuickCSV.dmg (2.1 MB) |

## Requirements

- macOS 13.0+ (Ventura)
- Swift 5.9+
- XcodeGen (`brew install xcodegen`)

## License

MIT License

---

*11 commits · 5,455 lines of Swift · RFC 4180 compliant · 4 view modes*
