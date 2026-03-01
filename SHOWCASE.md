# QLQuickCSV — Project Showcase

> **The one-sentence pitch:** A macOS app and Quick Look extension that
> turns pressing Space on a `.csv` file into an interactive data table
> with type detection, statistics, sorting, filtering, and multi-format
> export — because CSV files are data, not text.

---

## What Does It Actually Do?

Two things, sharing one rendering engine:

**1. Quick Look Extension** — Press Space on any `.csv` or `.tsv` file
in Finder and see an interactive table with sticky headers, column type
badges, sorting, filtering, statistics panel, search, and dark/light
theme support.

**2. Host App** — A SwiftUI document viewer with tabbed windows, an
Open Files Navigator for managing your workspace, session persistence,
zoom controls, and settings for themes and display preferences.

```
  BEFORE (default macOS)              AFTER (QLQuickCSV)
  ┌─────────────────────────┐        ┌──────────────────────────────────┐
  │ id,name,email,amount    │        │ ┌ Header ────────────────────┐   │
  │ 1,Alice,alice@co,1250   │        │ │ sales_data.csv · 2.4 MB   │   │
  │ 2,Bob,bob@co,3400       │        │ │ 15,000 rows · 8 columns    │   │
  │ 3,Carol,carol@co,890    │        │ │ [Copy Path] [GitHub]       │   │
  │ 4,Dave,dave@co,5200     │        │ └────────────────────────────┘   │
  │ 5,Eve,eve@co,2100       │        │                                  │
  │ ...                     │        │ ┌ Table (sorted by amount ▼) ──┐ │
  │                         │        │ │ id▾  name▾  email▾ amount▾  │ │
  │ 14998,Yuki,yuki@co,780  │        │ │ INT  TEXT   TEXT   DECIMAL  │ │
  │ 14999,Zach,zach@co,1430 │        │ ├────────────────────────────┤ │
  │ 15000,Zoe,zoe@co,620   │        │ │  4   Dave   dave   5,200   │ │
  │                         │        │ │  2   Bob    bob    3,400   │ │
  │ Raw text. No types,     │        │ │  5   Eve    eve    2,100   │ │
  │ no sorting, no totals.  │        │ │  ...                       │ │
  └─────────────────────────┘        │ └────────────────────────────┘ │
                                     │                                  │
                                     │  Views: [Table] [Markdown] [JSON]│
                                     │         [Raw]                    │
                                     └──────────────────────────────────┘
```

---

## Feature Map

```
┌─────────────────────────────────────────────────────────────────────┐
│                    QLQUICKCSV FEATURES                               │
├──────────────────┬───────────────────┬──────────────────────────────┤
│  QUICK LOOK      │  DATA ENGINE      │  APP FEATURES                │
│  ──────────      │  ───────────      │  ────────────                │
│  • Press Space   │  • RFC 4180 CSV   │  • Tabbed document windows   │
│    to preview    │    compliant      │  • Open Files Navigator      │
│  • File metadata │  • Auto-detect    │  • Session persistence       │
│    (size, dates) │    delimiter      │  • Zoom controls             │
│  • Git repo      │  • 4 encodings    │  • Word wrap toggle          │
│    detection     │    (UTF-8, 16,    │  • Search across data        │
│  • GitHub URLs   │    CP1252, Latin) │  • Editor integration        │
│    (blob/blame)  │  • Header auto-   │    (VS Code, Sublime)        │
│  • Download      │    detection      │  • Always on top             │
│    source info   │  • Type badges:   │                              │
│                  │    INT, DECIMAL,  │  VIEW MODES                  │
│  TABLE FEATURES  │    DATE, BOOL,    │  ──────────                  │
│  ──────────────  │    TEXT, MIXED    │  • Table (interactive)       │
│  • Sticky headers│  • Column stats   │  • Markdown (for sharing)    │
│  • Click to sort │    (min/max/avg)  │  • JSON (for APIs)           │
│  • Filter by     │  • Top values     │  • Raw text (original)       │
│    value         │    frequency      │                              │
│  • Copy buttons  │  • Row count      │  EXPORT                      │
│  • Cell expand   │    management     │  ──────                      │
│  • Line numbers  │                   │  • CSV, Markdown, JSON, SQL  │
│  • Dark/Light    │                   │                              │
└──────────────────┴───────────────────┴──────────────────────────────┘
```

---

## The Rendering Pipeline

What happens when you press Space on a `.csv` file:

```
  Press Space          Extension loads     Parsing &            HTML Assembly
  on .csv file    →    reads file,    →   analysis         →   table + JS +
  in Finder            detects encoding   (types, stats)       CSS + themes

         │
         ▼

  ┌─────────────────────────────────────────────────────────────┐
  │                   RENDERING PIPELINE                        │
  │                                                             │
  │  1. Read file content                                       │
  │     Try: UTF-8 → UTF-16 → CP1252 → ISO Latin-1             │
  │                         │                                   │
  │  2. CSVParser.parse()                                       │
  │     ┌──────────────────────────────────────────┐            │
  │     │ • Auto-detect delimiter (comma, tab,      │            │
  │     │   semicolon, pipe) via consistency score  │            │
  │     │ • RFC 4180 state machine: handle quoted   │            │
  │     │   fields, escaped quotes, newlines        │            │
  │     │ • Auto-detect headers (unique values,     │            │
  │     │   no-numbers, common patterns)            │            │
  │     │ • Normalize line endings (\r\n, \r → \n)  │            │
  │     └──────────────────────────────────────────┘            │
  │                         │                                   │
  │  3. CSVAnalyzer.analyze()                                   │
  │     ┌──────────────────────────────────────────┐            │
  │     │ • Detect column types: integer, decimal,  │            │
  │     │   date (12 formats), boolean, text, mixed │            │
  │     │ • Compute statistics per column:          │            │
  │     │   count, distinct, nulls, min/max/avg     │            │
  │     │ • Track top values with frequency counts  │            │
  │     │ • "Mixed" type = data quality signal      │            │
  │     └──────────────────────────────────────────┘            │
  │                         │                                   │
  │  4. HTMLGenerator.generate()                                │
  │     ┌──────────────────────────────────────────┐            │
  │     │ • Build table with sticky headers         │            │
  │     │ • Color-coded type badges per column      │            │
  │     │ • Inline all CSS (1,296 ln) + JS (~800 ln)│            │
  │     │ • Theme (GitHub/Monokai/Atom/Nord)        │            │
  │     │ • Sorting + filtering + stats JavaScript  │            │
  │     │ • Truncate to maxDisplayRows (1000)       │            │
  │     │ → One self-contained HTML string          │            │
  │     └──────────────────────────────────────────┘            │
  │                         │                                   │
  │  5. Return QLPreviewReply(dataOfContentType: .html)         │
  └─────────────────────────────────────────────────────────────┘
```

---

## Architecture: Shared Engine, Two Targets

```
┌──────────────────────────────────────────────────────────────────┐
│                                                                  │
│  ┌──────────────────────┐    ┌───────────────────────┐          │
│  │  CSVQLExtension      │    │   QLQuickCSV App      │          │
│  │  (Quick Look .appex) │    │   (SwiftUI Host)      │          │
│  │                      │    │                        │          │
│  │  PreviewViewController    │  Settings UI           │          │
│  │  99 lines            │    │  Open Files Navigator  │          │
│  │  QLPreviewReply      │    │  Session persistence   │          │
│  │  (data-based HTML)   │    │  Document viewer       │          │
│  └────────┬─────────────┘    └───────────┬────────────┘          │
│           │                              │                       │
│           └──────────┬───────────────────┘                       │
│                      │  both compile                             │
│                      ▼                                           │
│  ┌──────────────────────────────────────────────────┐           │
│  │              Shared/ (Data Engine)                │           │
│  │                                                  │           │
│  │  CSVParser ────── RFC 4180 state machine (453 ln) │           │
│  │  CSVAnalyzer ──── type detection + stats (374 ln) │           │
│  │  HTMLGenerator ── table + JS + CSS (1,817 ln)     │           │
│  │  Settings ─────── CFPreferences cross-process     │           │
│  │  GitHelper ────── .git/ direct reading            │           │
│  └──────────────────────────────────────────────────┘           │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

---

## By The Numbers

```
┌──────────────────────────────────────────────────┐
│                                                  │
│   5,455  lines of Swift source code              │
│      11  git commits                             │
│                                                  │
│   1,817  lines in HTMLGenerator (rendering)      │
│     453  lines in CSVParser (RFC 4180)           │
│     374  lines in CSVAnalyzer (type detection)   │
│   1,129  lines in Open Files Navigator           │
│                                                  │
│    ~800  lines of inline JavaScript              │
│   1,296  lines of inline CSS                     │
│                                                  │
│      12  date format patterns recognized         │
│       4  encoding fallbacks                      │
│       4  delimiter types auto-detected           │
│       4  view modes (table, markdown, JSON, raw) │
│       4  color themes                            │
│                                                  │
│    Build: XcodeGen → xcodebuild → DMG            │
│    Distribution: QLQuickCSV.dmg (2.1 MB)         │
│                                                  │
└──────────────────────────────────────────────────┘
```

---

## What Makes It Interesting (Engineering Highlights)

### 1. RFC 4180 CSV Parsing (State Machine)

CSV parsing is deceptively complex. Naive string splitting fails on
quoted fields with commas, escaped quotes, and embedded newlines.
The parser uses a proper state machine with an `inQuotes` flag and
lookahead for escaped quote pairs (`""`).

### 2. Delimiter Auto-Detection

Instead of assuming commas, the parser samples the first 10 lines
and scores each possible delimiter (comma, tab, semicolon, pipe)
on field consistency (70%) and column count (30%). The highest
score wins — so TSV files, European CSVs with semicolons, and
pipe-delimited files all work automatically.

### 3. The "Mixed" Type is a Feature

When CSVAnalyzer detects multiple types in one column (e.g., 95%
integers + 5% text), it labels the column "mixed" instead of
forcing a type. This signals a data quality issue worth investigating
— better than silently choosing the wrong type.

### 4. Header Auto-Detection

Smart algorithm checks: Does the first row contain only numbers?
Are all first-row values unique? Do they match common header
patterns (id, name, type, date)? Are data rows longer than the
first row?

### 5. Self-Contained HTML (Zero External Requests)

The entire preview — interactive table, sorting JavaScript, theme
CSS, statistics panel — is a single HTML string with no external
dependencies. Renders instantly with no network calls.

### 6. Large File Handling

Files with 100k+ rows are truncated to `maxDisplayRows` (default
1000) with a "showing X of Y rows" indicator. Keeps the preview
responsive while still being useful for data exploration.

---

## Evolution Story

```
  v1.0: Initial Release                             ~Feb 2026
  ──────────────────────
  Core CSV parsing, syntax highlighting, GitHub
  integration, multiple view modes (table, markdown,
  JSON, raw). Type detection and statistics panel.


  v1.1: Window Management                           ~Feb 2026
  ────────────────────────
  Open Files Navigator, word wrap, cell expand/
  collapse, app icon, TXT view mode. Full session
  management with tab groups and sorting.


  v1.2-1.3: Polish                                  ~Feb 2026
  ────────────────────
  Cmd+R reload, line ending normalization (Windows/
  Mac), header toggle feature, header detection
  bug fixes. Stable release.
```

---

## Project Structure

```
quicklook-csv/
│
├── CSVQLExtension/                ← Quick Look extension (.appex)
│   └── PreviewViewController.swift   QLPreviewingController (99 ln)
│
├── QLQuickCSV/                    ← SwiftUI host app
│   ├── QLQuickCSVApp.swift           Entry point (152 ln)
│   ├── ContentView.swift             Settings UI (433 ln)
│   ├── CSVDocument.swift             FileDocument model
│   ├── CSVDocumentView.swift         WebView viewer (266 ln)
│   ├── OpenFilesNavigator.swift      File navigator (1,129 ln)
│   └── SessionManager.swift          Session persistence (275 ln)
│
├── Shared/                        ← Data engine (both targets)
│   ├── CSVParser.swift               RFC 4180 state machine (453 ln)
│   ├── CSVAnalyzer.swift             Type detection + stats (374 ln)
│   ├── HTMLGenerator.swift           Table + JS + CSS (1,817 ln)
│   ├── Settings.swift                CFPreferences wrapper
│   └── GitHelper.swift               .git/ direct reading
│
├── project.yml                    ← XcodeGen project definition
├── build-release.sh               ← DMG packaging
└── test-data/                     ← Sample CSV and TSV files
```

---

## The "Explain It To A Friend" Version

> "You know how CSV files — spreadsheet data exported as text — look
> terrible when you preview them in Finder? Just raw commas and text,
> no structure, no types, no way to sort or explore.
>
> I built a Quick Look extension that renders them as proper data
> tables — sticky headers, color-coded type badges (integer, decimal,
> date, text), click-to-sort columns, a statistics panel showing
> min/max/average per column, and a filter that lets you click a
> value to see all matching rows.
>
> The parser handles edge cases that trip up naive CSV readers —
> quoted fields with commas inside, escaped quotes, embedded newlines,
> and it auto-detects the delimiter (commas, tabs, semicolons, pipes)
> by scoring consistency across the first 10 lines.
>
> Then I built a host app around it with tabbed windows and a file
> navigator, so you can open multiple CSVs and explore them with
> zoom, search, and session persistence."

---

*11 commits · 5,455 lines of Swift · 4 view modes · RFC 4180 compliant*
