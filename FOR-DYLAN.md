# FOR-DYLAN.md - QLQuickCSV Deep Dive

Hey Dylan! This document explains the QLQuickCSV project in plain language—the architecture, the decisions, the lessons learned. It's designed to be engaging and educational, not dry technical documentation.

---

## What Does This Project Do?

**QLQuickCSV** is a macOS Quick Look extension that transforms how you preview CSV and TSV files. Instead of seeing a wall of comma-separated text, you see an interactive HTML table—like a mini spreadsheet right in Finder.

**The Philosophy**: CSV files are *data*, not *text*. They deserve to be rendered as tables, not shown as raw strings.

Think of it like the difference between reading a novel in manuscript format versus a professionally typeset book. Same content, dramatically different experience.

---

## The Two-App Architecture

Here's something that trips people up: Quick Look extensions on macOS aren't standalone apps. They're plugins that live inside a "host app."

```
QLQuickCSV.app (Host App)
└── Contents/
    └── PlugIns/
        └── CSVQLExtension.appex (The actual Quick Look extension)
```

**Why two apps?**

1. **The Extension** (`CSVQLExtension.appex`) is what Finder calls when you press Space on a CSV file. It's sandboxed, limited, and can only read the specific file it's asked to preview.

2. **The Host App** (`QLQuickCSV.app`) serves three purposes:
   - **Registration**: When you open it, macOS learns about the extension and registers it
   - **Settings**: Users configure preferences here (max rows, theme, etc.)
   - **Document Viewer**: You can actually open CSV files directly in the app, with all the interactive features

**The Settings Problem**: Here's a classic macOS challenge—the extension and host app are separate processes with separate sandboxes. How do they share settings?

The answer is `CFPreferences` with a shared app group. The host app writes to `com.qlcsv.shared.plist`, and the extension reads from the host app's container. It's a bit hacky (reading another app's plist directly), but it works reliably.

---

## The Data Flow: From Space Bar to Table

When you press Space on a CSV file in Finder, here's what happens:

```
1. Finder → Quick Look Daemon
   "Hey, preview this file: /path/to/data.csv"

2. Quick Look Daemon → CSVQLExtension
   "Your turn. Here's a QLFilePreviewRequest."

3. CSVQLExtension.PreviewViewController
   └── CSVParser.parse(content)        → CSVData struct
   └── CSVAnalyzer.analyzeCSV(data)    → Column statistics
   └── GitHelper.getGitInfo(path)      → GitHub URL (optional)
   └── HTMLGenerator.generate(...)      → Complete HTML string

4. Returns QLPreviewReply with HTML data

5. Quick Look Daemon renders HTML in its WebView
```

The key insight: **We return HTML, not a view**. Modern Quick Look (macOS 12+) supports `QLIsDataBasedPreview = true`, which means we can return raw HTML data. The system handles the WebView—we just provide the content.

This is brilliant because:
- We get full JavaScript interactivity (sorting, filtering, searching)
- Our code is simpler (no view lifecycle management)
- It's faster (no bridging between Swift views and WebView)

---

## The CSV Parser: Harder Than You Think

"Just split on commas, right?"

Oh, if only. Here's a CSV that breaks naive parsers:

```csv
Name,Quote,Price
"Smith, John","He said ""Hello""",1234.56
"Multi
Line",Value,789
```

That's valid CSV (RFC 4180). Notice:
- Commas inside quoted fields
- Escaped quotes (doubled: `""`)
- Newlines inside quoted fields

**Our parser handles all of this** by maintaining state:
- `inQuotes`: Are we inside a quoted field?
- Lookahead for escaped quotes (`""` → single `"`)
- Accumulating characters into fields

**Delimiter Auto-Detection**: We also detect whether a file uses commas, tabs, semicolons, or pipes. The algorithm:
1. Take the first 10 lines
2. For each possible delimiter, count how many fields per line
3. Score based on consistency (do all lines have the same field count?)
4. Pick the delimiter with the highest score

---

## Column Type Detection: Pattern Matching

When you see a column, we tell you what *type* of data it contains:

```
| Type     | Detection Pattern                    |
|----------|--------------------------------------|
| integer  | ^-?\d+$                              |
| decimal  | ^-?\d+\.\d+$ (with comma handling)   |
| date     | Various formats (ISO, US, EU)        |
| boolean  | true/false/yes/no/1/0                |
| text     | Everything else                      |
| mixed    | Multiple types in same column        |
```

**The Challenge**: What if a column has 95% integers and 5% text? We call it "mixed" rather than forcing a type. This is important for data quality signals—a "mixed" type often indicates dirty data.

**Statistics We Calculate**:
- Count (total rows)
- Non-empty count (excludes blanks)
- Distinct count (unique values)
- Min/Max (for numeric/date types)
- Sum/Average (for numeric types)
- Top values with frequency counts

---

## The HTML Generator: 1200 Lines of Craft

This is the most complex file. It generates a complete, self-contained HTML document with:
- Responsive CSS for light/dark modes
- Interactive JavaScript for sorting, filtering, searching
- Sticky headers (always visible while scrolling)
- Stats panel (shows when you click a column)
- Multiple view modes (Table, Markdown, JSON)

**Why embed everything?** Quick Look extensions can't load external resources reliably. Everything—CSS, JS, data—must be in one HTML string.

**The Security Note**: We use `insertAdjacentHTML` and DOM manipulation carefully. All data comes from local CSV files (not user input), so XSS isn't a concern, but we still:
- Escape HTML in cell values
- Use `textContent` where possible
- Build stats panel with `createElement` rather than string templates

---

## Lessons Learned (The Hard Way)

### 1. NSAppearance Isn't Always Available

The extension runs in a context where `NSAppearance.current` can be nil or deprecated. Our workaround:

```swift
#if canImport(AppKit)
import AppKit
#endif
```

And we check for appearance carefully:
```swift
if let appearance = NSAppearance.current?.name {
    return appearance == .darkAqua || ...
}
return false
```

### 2. The "Extension Not Loading" Dance

Quick Look extensions are notoriously finicky. If your extension isn't working:

```bash
# The nuclear option
pluginkit -e ignore -i com.qlcsv.QLQuickCSV.CSVQLExtension
killall quicklookd
qlmanage -r cache && qlmanage -r
# Reinstall and reopen host app
```

### 3. CFPreferences Cross-Process Gotcha

Writing settings in the host app and reading them in the extension requires:
- Using the same app group/domain
- Calling `CFPreferencesAppSynchronize` after writes
- Reading from the host app's container in the extension

### 4. UTF Type Identifiers Matter

CSV files use `public.comma-separated-values-text`, not some custom UTI. If you declare the wrong type, Quick Look won't call your extension.

---

## How Good Engineers Think About This

**1. User Experience First**: The whole project exists because raw CSV text is bad UX. We started with "what would users want?" and worked backward to the implementation.

**2. Self-Contained Outputs**: The HTML we generate has zero external dependencies. This makes it:
   - Predictable (no network requests)
   - Fast (no loading delays)
   - Reliable (works offline)

**3. Graceful Degradation**: If a file is huge (100k rows), we:
   - Truncate to `maxDisplayRows` (default: 1000)
   - Show a "X of Y rows" indicator
   - Keep the preview responsive

**4. Separation of Concerns**:
   - `CSVParser`: Just parsing, no analysis
   - `CSVAnalyzer`: Just statistics, no rendering
   - `HTMLGenerator`: Just rendering, no file I/O
   - `PreviewViewController`: Just orchestration

This makes each piece testable and modifiable in isolation.

---

## Technologies Worth Learning From

### 1. XcodeGen (`project.yml`)

Instead of managing `*.xcodeproj` (which is an opaque mess), we describe the project in YAML:

```yaml
targets:
  QLQuickCSV:
    type: application
    dependencies:
      - target: CSVQLExtension
        embed: true
```

One `xcodegen generate` command creates the Xcode project. This is huge for:
- Clean diffs in version control
- Understanding project structure at a glance
- Avoiding Xcode merge conflicts

### 2. Quick Look Data-Based Previews

The `QLIsDataBasedPreview = true` approach is newer and cleaner than view-based previews. It's worth understanding for any file preview work.

### 3. Swift's String Index Handling

Our CSV parser uses Swift's index-based string iteration:
```swift
var i = content.startIndex
while i < content.endIndex {
    let char = content[i]
    i = content.index(after: i)
}
```

This is more verbose than `for char in content`, but we need lookahead capability for escaped quotes.

---

## Project Structure at a Glance

```
quicklook-csv/
├── project.yml              # XcodeGen project definition
├── build-release.sh         # Creates DMG/ZIP for distribution
├── CLAUDE.md                # Claude Code instructions
├── FOR-DYLAN.md             # This file!
│
├── Shared/                  # Code shared between app and extension
│   ├── CSVParser.swift      # RFC 4180 compliant parsing
│   ├── CSVAnalyzer.swift    # Type detection & statistics
│   ├── HTMLGenerator.swift  # The big one: HTML table generation
│   ├── Settings.swift       # Cross-process settings
│   └── GitHelper.swift      # Git/GitHub URL detection
│
├── QLQuickCSV/              # Host SwiftUI app
│   ├── QLQuickCSVApp.swift  # App entry point
│   ├── ContentView.swift    # Settings/About UI
│   ├── CSVDocument.swift    # FileDocument model
│   └── CSVDocumentView.swift # WebView-based viewer
│
├── CSVQLExtension/          # Quick Look extension
│   ├── PreviewViewController.swift  # QLPreviewingController
│   └── Info.plist           # Extension configuration
│
└── test-data/               # Sample files for testing
    ├── sample.csv
    └── sample.tsv
```

---

## Running It

```bash
# Generate Xcode project
xcodegen generate

# Build
xcodebuild -scheme QLQuickCSV build

# Install
cp -R build/Build/Products/Debug/QLQuickCSV.app /Applications/

# Open to register, then enable in System Settings
open /Applications/QLQuickCSV.app

# Test
qlmanage -p /path/to/any.csv
```

---

## What Could Be Added

1. **Charts**: The Phase 6 plan includes auto-generated bar/line/pie charts from selected columns
2. **Conditional Formatting**: Heat maps and color scales for numeric columns
3. **Column Resize**: Drag borders to resize columns
4. **Export to File**: Save as JSON, Markdown, SQL, or formatted HTML

---

That's the QLQuickCSV story! The key takeaway: **good developer tools start with empathy for users**. CSV files have been around for 50+ years, but most tools still treat them as text. We treat them as data—and that changes everything.

Happy coding! 🎉
