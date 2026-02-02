//
//  OpenFilesNavigator.swift
//  QLQuickCSV
//
//  Navigator window showing all open CSV files with grouping, sorting, search,
//  Find in Files, drag-and-drop reordering, and comprehensive file management.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Open Files Navigator

struct OpenFileInfo: Identifiable, Hashable {
    let id: URL
    let fileName: String
    let filePath: String
    let folderPath: String
    let fileSize: String
    let modifiedDate: String
    let modifiedAgo: String
    let lineCount: Int
    let tabIndex: Int  // Position within the tab group
    let openedAt: Date  // When this file was opened in the app

    var url: URL { id }
}

struct WindowGroupInfo: Identifiable, Equatable {
    let id: ObjectIdentifier  // Runtime identifier for the window/tab group
    let stableId: UUID        // Stable identifier for persistence across launches
    let windowNumber: Int
    let isKeyWindow: Bool
    let tabCount: Int
    var files: [OpenFileInfo]
    var customName: String?   // User-defined name for this group

    var displayName: String {
        if let name = customName, !name.isEmpty {
            return name
        }
        if tabCount == 1, let firstFile = files.first {
            return firstFile.fileName
        }
        return "Window \(windowNumber) (\(tabCount) tab\(tabCount == 1 ? "" : "s"))"
    }

    static func == (lhs: WindowGroupInfo, rhs: WindowGroupInfo) -> Bool {
        lhs.id == rhs.id && lhs.stableId == rhs.stableId && lhs.windowNumber == rhs.windowNumber && lhs.tabCount == rhs.tabCount && lhs.files == rhs.files && lhs.customName == rhs.customName
    }
}

@MainActor
class OpenFilesModel: ObservableObject {
    // Singleton for AppDelegate access
    static weak var shared: OpenFilesModel?

    @Published var windowGroups: [WindowGroupInfo] = []
    @Published var customGroupNames: [UUID: String] = [:]  // Stable ID -> custom name
    @Published var displayOrders: [UUID: [URL: Int]] = [:]  // Stable ID -> URL display order
    @Published var activeFileURL: URL?  // Currently active file for selection sync
    @Published var fileOpenTimes: [URL: Date] = [:]  // Track when each file was opened

    private var observers: [Any] = []
    private var windowToStableId: [ObjectIdentifier: UUID] = [:]  // Maps runtime IDs to stable IDs
    private var groupOrder: [UUID] = []  // Stable order of groups (first-seen order)
    private var tabOrderCheckTimer: Timer?
    private var lastKnownTabOrder: [UUID: [URL]] = [:]  // Track tab order per group to detect changes

    var totalFileCount: Int {
        windowGroups.reduce(0) { $0 + $1.files.count }
    }

    /// Can merge if there are multiple window groups
    var canMergeAll: Bool {
        windowGroups.count > 1
    }

    /// Can separate if any window group has more than 1 tab
    var canSeparateAll: Bool {
        windowGroups.contains { $0.tabCount > 1 }
    }

    init() {
        OpenFilesModel.shared = self

        // Observe document changes
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        })
        observers.append(nc.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor in
                self?.updateActiveFile(from: notification)
                self?.updateKeyWindowStatus()
            }
        })
        observers.append(nc.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                self?.refresh()
            }
        })

        // Start autosave
        SessionManager.shared.startAutosave(model: self)

        // Start tab order monitoring (checks every 0.5s for tab reordering in the app)
        startTabOrderMonitoring()

        refresh()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        tabOrderCheckTimer?.invalidate()
        SessionManager.shared.stopAutosave()
    }

    /// Starts a lightweight timer to detect tab reordering in the app
    private func startTabOrderMonitoring() {
        tabOrderCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForTabOrderChanges()
            }
        }
    }

    /// Checks if tabs have been reordered in any window and updates if needed
    private func checkForTabOrderChanges() {
        var currentTabOrder: [UUID: [URL]] = [:]
        var hasChanges = false

        // Build current tab order for each window group
        for document in NSDocumentController.shared.documents {
            guard let windowController = document.windowControllers.first,
                  let window = windowController.window,
                  let url = document.fileURL else { continue }

            let groupWindow: NSWindow
            if let tabGroup = window.tabGroup, let firstWindow = tabGroup.windows.first {
                groupWindow = firstWindow
            } else {
                groupWindow = window
            }

            let objectId = ObjectIdentifier(groupWindow)
            guard let stableId = windowToStableId[objectId] else { continue }

            if currentTabOrder[stableId] == nil {
                currentTabOrder[stableId] = []
            }

            // Get the actual tab index from the tab group
            let tabIndex: Int
            if let tabGroup = window.tabGroup {
                tabIndex = tabGroup.windows.firstIndex(of: window) ?? 0
            } else {
                tabIndex = 0
            }

            // Ensure array is large enough
            while currentTabOrder[stableId]!.count <= tabIndex {
                currentTabOrder[stableId]!.append(URL(fileURLWithPath: "/placeholder"))
            }
            currentTabOrder[stableId]![tabIndex] = url
        }

        // Clean up placeholder URLs
        for (key, urls) in currentTabOrder {
            currentTabOrder[key] = urls.filter { $0.path != "/placeholder" }
        }

        // Compare with last known order
        for (stableId, urls) in currentTabOrder {
            if let lastUrls = lastKnownTabOrder[stableId] {
                if urls != lastUrls {
                    hasChanges = true
                    break
                }
            } else {
                hasChanges = true
                break
            }
        }

        // Also check if any groups were removed
        if !hasChanges {
            for stableId in lastKnownTabOrder.keys {
                if currentTabOrder[stableId] == nil {
                    hasChanges = true
                    break
                }
            }
        }

        if hasChanges {
            lastKnownTabOrder = currentTabOrder
            refresh()
        }
    }

    /// Updates the active file URL when a window becomes key
    private func updateActiveFile(from notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }

        // Find the document for this window
        for document in NSDocumentController.shared.documents {
            if let wc = document.windowControllers.first,
               wc.window == window,
               let url = document.fileURL {
                activeFileURL = url
                return
            }
        }
    }

    /// Updates only the key window status without reordering groups
    private func updateKeyWindowStatus() {
        let keyWindow = NSApp.keyWindow

        // Update isKeyWindow flag for each group without reordering
        windowGroups = windowGroups.map { group in
            // Find the window for this group
            var isKey = false
            for document in NSDocumentController.shared.documents {
                if let wc = document.windowControllers.first,
                   let window = wc.window,
                   group.files.contains(where: { $0.url == document.fileURL }) {
                    if window == keyWindow || window.tabGroup?.windows.contains(keyWindow ?? NSWindow()) == true {
                        isKey = true
                        break
                    }
                }
            }

            return WindowGroupInfo(
                id: group.id,
                stableId: group.stableId,
                windowNumber: group.windowNumber,
                isKeyWindow: isKey,
                tabCount: group.tabCount,
                files: group.files,
                customName: group.customName
            )
        }
    }

    /// Gets or creates a stable UUID for a window's ObjectIdentifier
    private func stableId(for objectId: ObjectIdentifier) -> UUID {
        if let existing = windowToStableId[objectId] {
            return existing
        }
        let newId = UUID()
        windowToStableId[objectId] = newId
        return newId
    }

    /// Renames a window group
    func renameGroup(stableId: UUID, to newName: String?) {
        if let name = newName, !name.isEmpty {
            customGroupNames[stableId] = name
        } else {
            customGroupNames.removeValue(forKey: stableId)
        }
        refresh()
        // Save session after rename
        SessionManager.shared.saveSession(from: self)
    }

    /// Updates display order for files within a group
    func updateDisplayOrder(groupId: UUID, orderedURLs: [URL]) {
        var order: [URL: Int] = [:]
        for (index, url) in orderedURLs.enumerated() {
            order[url] = index
        }
        displayOrders[groupId] = order
    }

    /// Gets the display order for a file within a group (nil = use natural order)
    func displayOrder(for url: URL, in groupId: UUID) -> Int? {
        displayOrders[groupId]?[url]
    }

    func refresh() {
        // Group documents by their window's tab group
        var windowToFiles: [ObjectIdentifier: (window: NSWindow, files: [(doc: NSDocument, tabIndex: Int)])] = [:]
        let keyWindow = NSApp.keyWindow

        for document in NSDocumentController.shared.documents {
            guard let windowController = document.windowControllers.first,
                  let window = windowController.window else { continue }

            // Use the tab group's first window as the group identifier, or the window itself
            let groupWindow: NSWindow
            if let tabGroup = window.tabGroup, let firstWindow = tabGroup.windows.first {
                groupWindow = firstWindow
            } else {
                groupWindow = window
            }

            let groupId = ObjectIdentifier(groupWindow)

            // Find tab index within the group
            let tabIndex: Int
            if let tabGroup = window.tabGroup {
                tabIndex = tabGroup.windows.firstIndex(of: window) ?? 0
            } else {
                tabIndex = 0
            }

            if windowToFiles[groupId] == nil {
                windowToFiles[groupId] = (window: groupWindow, files: [])
            }
            windowToFiles[groupId]?.files.append((doc: document, tabIndex: tabIndex))
        }

        // Convert to WindowGroupInfo array
        var groups: [WindowGroupInfo] = []
        var windowNumber = 1

        // Build stable IDs for all current groups
        var currentStableIds: [UUID: (objectId: ObjectIdentifier, data: (window: NSWindow, files: [(doc: NSDocument, tabIndex: Int)]))] = [:]
        for (objectId, data) in windowToFiles {
            let stableId = self.stableId(for: objectId)
            currentStableIds[stableId] = (objectId: objectId, data: data)

            // Add new groups to the order list
            if !groupOrder.contains(stableId) {
                groupOrder.append(stableId)
            }
        }

        // Remove stale groups from order
        groupOrder.removeAll { !currentStableIds.keys.contains($0) }

        // Process groups in stable order
        for groupStableId in groupOrder {
            guard let entry = currentStableIds[groupStableId] else { continue }
            let groupId = entry.objectId
            let groupData = entry.data
            let isKey = groupData.window == keyWindow || groupData.window.tabGroup?.windows.contains(keyWindow ?? NSWindow()) == true

            // Sort files by display order if available, otherwise by tab index
            var sortedFiles = groupData.files.sorted { $0.tabIndex < $1.tabIndex }

            // Apply custom display order if set
            if let displayOrder = displayOrders[groupStableId] {
                sortedFiles.sort { lhs, rhs in
                    let lhsOrder = lhs.doc.fileURL.flatMap { displayOrder[$0] } ?? Int.max
                    let rhsOrder = rhs.doc.fileURL.flatMap { displayOrder[$0] } ?? Int.max
                    if lhsOrder != rhsOrder {
                        return lhsOrder < rhsOrder
                    }
                    return lhs.tabIndex < rhs.tabIndex
                }
            }

            let fileInfos = sortedFiles.compactMap { item -> OpenFileInfo? in
                guard let url = item.doc.fileURL else { return nil }
                return createFileInfo(from: url, tabIndex: item.tabIndex)
            }

            if !fileInfos.isEmpty {
                groups.append(WindowGroupInfo(
                    id: groupId,
                    stableId: groupStableId,
                    windowNumber: windowNumber,
                    isKeyWindow: isKey,
                    tabCount: fileInfos.count,
                    files: fileInfos,
                    customName: customGroupNames[groupStableId]
                ))
                windowNumber += 1
            }
        }

        // Update with animation for smoother transitions
        withAnimation(.easeInOut(duration: 0.2)) {
            windowGroups = groups
        }

        // Update the tab order cache to prevent duplicate refreshes
        var newTabOrder: [UUID: [URL]] = [:]
        for group in groups {
            newTabOrder[group.stableId] = group.files.map { $0.url }
        }
        lastKnownTabOrder = newTabOrder
    }

    private func createFileInfo(from url: URL, tabIndex: Int) -> OpenFileInfo {
        let path = url.path
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)

        let fileSize: String
        if let size = attributes?[.size] as? Int64 {
            fileSize = formatFileSize(size)
        } else {
            fileSize = ""
        }

        let modifiedDate: String
        let modifiedAgo: String
        if let date = attributes?[.modificationDate] as? Date {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            modifiedDate = formatter.string(from: date)
            modifiedAgo = formatTimeAgo(from: date)
        } else {
            modifiedDate = ""
            modifiedAgo = ""
        }

        let lineCount: Int
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            lineCount = content.components(separatedBy: "\n").count
        } else {
            lineCount = 0
        }

        // Get or create the opened time for this file
        let openedAt: Date
        if let existingTime = fileOpenTimes[url] {
            openedAt = existingTime
        } else {
            openedAt = Date()
            fileOpenTimes[url] = openedAt
        }

        return OpenFileInfo(
            id: url,
            fileName: url.lastPathComponent,
            filePath: path,
            folderPath: url.deletingLastPathComponent().path,
            fileSize: fileSize,
            modifiedDate: modifiedDate,
            modifiedAgo: modifiedAgo,
            lineCount: lineCount,
            tabIndex: tabIndex,
            openedAt: openedAt
        )
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var size = Double(bytes)
        var unitIndex = 0
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(Int(size)) \(units[unitIndex])"
        }
        return String(format: "%.1f %@", size, units[unitIndex])
    }

    private func formatTimeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let seconds = Int(interval)

        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 7 { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 4 { return "\(weeks)w ago" }
        let months = days / 30
        if months < 12 { return "\(months)mo ago" }
        return "\(days / 365)y ago"
    }

    func activateFile(_ file: OpenFileInfo) {
        // Find the document and its window
        for document in NSDocumentController.shared.documents {
            if document.fileURL == file.url {
                document.showWindows()
                if let windowController = document.windowControllers.first,
                   let window = windowController.window {
                    window.makeKeyAndOrderFront(nil)
                }
                break
            }
        }
    }

    /// Checks if a file URL appears in multiple window groups
    func isDuplicate(_ url: URL) -> Bool {
        var count = 0
        for group in windowGroups {
            if group.files.contains(where: { $0.url == url }) {
                count += 1
                if count > 1 { return true }
            }
        }
        return false
    }

    /// Closes a file by URL
    func closeFile(_ url: URL) {
        for document in NSDocumentController.shared.documents {
            if document.fileURL == url {
                document.close()
                break
            }
        }
    }

    /// Tracks recently closed files for quick reopen
    @Published var recentlyClosed: [URL] = []
    private let maxRecentlyClosed = 10

    /// Adds a file to the recently closed list
    func trackClosedFile(_ url: URL) {
        // Remove if already in list
        recentlyClosed.removeAll { $0 == url }
        // Add to front
        recentlyClosed.insert(url, at: 0)
        // Trim to max
        if recentlyClosed.count > maxRecentlyClosed {
            recentlyClosed = Array(recentlyClosed.prefix(maxRecentlyClosed))
        }
    }

    /// Reopens a recently closed file
    func reopenFile(_ url: URL) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] document, _, error in
            guard document != nil, error == nil else { return }
            // Remove from recently closed
            Task { @MainActor in
                self?.recentlyClosed.removeAll { $0 == url }
            }
        }
    }

    // MARK: - Open Files

    /// Opens files from a file dialog
    func openFilesFromDialog() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "csv")!,
            UTType(filenameExtension: "tsv")!,
            UTType.commaSeparatedText
        ]
        panel.message = "Select CSV files to open"

        if panel.runModal() == .OK {
            for url in panel.urls {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
                    document?.showWindows()
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.refresh()
            }
        }
    }

    /// Imports file paths from clipboard
    func importFilesFromClipboard() {
        guard let clipboardString = NSPasteboard.general.string(forType: .string) else { return }

        let lines = clipboardString.components(separatedBy: .newlines)
        var validURLs: [URL] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Handle paths with or without file:// prefix
            let path: String
            if trimmed.hasPrefix("file://") {
                path = URL(string: trimmed)?.path ?? trimmed
            } else {
                path = trimmed
            }

            // Expand ~ to home directory
            let expandedPath = (path as NSString).expandingTildeInPath

            // Check if file exists and has valid extension
            let url = URL(fileURLWithPath: expandedPath)
            let ext = url.pathExtension.lowercased()
            if ["csv", "tsv", "txt"].contains(ext) && FileManager.default.fileExists(atPath: expandedPath) {
                validURLs.append(url)
            }
        }

        if validURLs.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No Valid Files Found"
            alert.informativeText = "No CSV files (.csv, .tsv) were found in the clipboard."
            alert.alertStyle = .informational
            alert.runModal()
            return
        }

        for url in validURLs {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, _ in
                document?.showWindows()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Merge/Separate Windows

    /// Merges all windows into one tabbed window
    func mergeAllWindows() {
        // Collect all URLs from all groups in order
        var allURLs: [URL] = []
        for group in windowGroups {
            for file in group.files {
                allURLs.append(file.url)
            }
        }

        guard allURLs.count > 1 else { return }

        // Close all documents
        for document in NSDocumentController.shared.documents {
            document.close()
        }

        // Reopen all as tabs in one window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.openDocumentsSequentially(urls: allURLs, index: 0, targetWindow: nil) {
                self?.refresh()
            }
        }
    }

    /// Separates all tabs into individual windows
    func separateAllWindows() {
        // Collect all URLs
        var allURLs: [URL] = []
        for group in windowGroups {
            for file in group.files {
                allURLs.append(file.url)
            }
        }

        guard !allURLs.isEmpty else { return }

        // Close all documents
        for document in NSDocumentController.shared.documents {
            document.close()
        }

        // Reopen each document in its own separate window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            let totalCount = allURLs.count
            var openedCount = 0

            for url in allURLs {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
                    openedCount += 1
                    guard let document = document, error == nil else {
                        if openedCount == totalCount {
                            Task { @MainActor in
                                self?.refresh()
                            }
                        }
                        return
                    }
                    document.showWindows()

                    // Refresh when all documents are opened
                    if openedCount == totalCount {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            Task { @MainActor in
                                self?.refresh()
                            }
                        }
                    }
                }
            }
        }
    }

    /// Opens documents sequentially, adding each as a tab to the target window
    private func openDocumentsSequentially(urls: [URL], index: Int, targetWindow: NSWindow?, completion: @escaping () -> Void) {
        guard index < urls.count else {
            completion()
            return
        }

        let url = urls[index]
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { [weak self] document, _, error in
            guard let document = document, error == nil else {
                // Skip failed document, continue with next
                self?.openDocumentsSequentially(urls: urls, index: index + 1, targetWindow: targetWindow, completion: completion)
                return
            }

            document.showWindows()

            // Get or set target window
            var nextTargetWindow = targetWindow
            if nextTargetWindow == nil, let wc = document.windowControllers.first, let window = wc.window {
                nextTargetWindow = window
            } else if let target = targetWindow, let wc = document.windowControllers.first, let window = wc.window {
                // Add as tab to target window
                target.addTabbedWindow(window, ordered: .above)
            }

            // Continue with next document
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.openDocumentsSequentially(urls: urls, index: index + 1, targetWindow: nextTargetWindow, completion: completion)
            }
        }
    }
}

// MARK: - Sort options

enum FileSortOption: String, CaseIterable {
    case tabOrder = "Tab Order"
    case recentlyOpened = "Recently Opened"
    case name = "Name"
    case dateModified = "Date Modified"
    case size = "Size"
    case lineCount = "Lines"
}

enum GroupByOption: String, CaseIterable {
    case window = "Window"
    case folder = "Folder"
}

// MARK: - Navigator View

struct OpenFilesNavigatorView: View {
    @StateObject private var model = OpenFilesModel()
    @State private var selectedFile: OpenFileInfo?
    @State private var searchText = ""
    @State private var expandedGroups: Set<ObjectIdentifier> = []
    @AppStorage("navigatorAlwaysOnTop") private var alwaysOnTop = false
    @AppStorage("navigatorSortOption") private var sortOption: FileSortOption = .tabOrder

    var filteredGroups: [WindowGroupInfo] {
        if searchText.isEmpty {
            return model.windowGroups
        }
        return model.windowGroups.compactMap { group in
            let filteredFiles = group.files.filter {
                $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                $0.filePath.localizedCaseInsensitiveContains(searchText)
            }
            guard !filteredFiles.isEmpty else { return nil }
            return WindowGroupInfo(
                id: group.id,
                stableId: group.stableId,
                windowNumber: group.windowNumber,
                isKeyWindow: group.isKeyWindow,
                tabCount: filteredFiles.count,
                files: filteredFiles,
                customName: group.customName
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Filter files...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // File count and toolbar
            HStack {
                Text("\(model.totalFileCount) file\(model.totalFileCount == 1 ? "" : "s") in \(filteredGroups.count) window\(filteredGroups.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button(action: { alwaysOnTop.toggle() }) {
                    Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                        .font(.caption)
                        .foregroundColor(alwaysOnTop ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
                .help(alwaysOnTop ? "Disable always on top" : "Keep window on top")

                Button(action: {
                    if expandedGroups.count == filteredGroups.count {
                        expandedGroups.removeAll()
                    } else {
                        expandedGroups = Set(filteredGroups.map { $0.id })
                    }
                }) {
                    Image(systemName: expandedGroups.count == filteredGroups.count ? "chevron.down.circle" : "chevron.right.circle")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Button(action: { model.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Refresh list")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // File list
            List(selection: $selectedFile) {
                ForEach(filteredGroups) { group in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedGroups.contains(group.id) },
                            set: { isExpanded in
                                if isExpanded {
                                    expandedGroups.insert(group.id)
                                } else {
                                    expandedGroups.remove(group.id)
                                }
                            }
                        )
                    ) {
                        ForEach(group.files) { file in
                            FileRowView(
                                file: file,
                                showTabIndex: group.tabCount > 1,
                                isActive: model.activeFileURL == file.url,
                                isDimmed: false,
                                isDuplicate: model.isDuplicate(file.url)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedFile = file
                                model.activateFile(file)
                            }
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.selectFile(file.filePath, inFileViewerRootedAtPath: file.folderPath)
                                }
                                Button("Copy File Path") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(file.filePath, forType: .string)
                                }
                                Divider()
                                Button("Close File") {
                                    model.trackClosedFile(file.url)
                                    model.closeFile(file.url)
                                }
                            }
                        }
                    } label: {
                        WindowGroupHeaderView(group: group) { newName in
                            model.renameGroup(stableId: group.stableId, to: newName)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .onAppear {
                expandedGroups = Set(model.windowGroups.map { $0.id })
            }

            Divider()

            // Action buttons
            HStack {
                // Add files menu
                Menu {
                    Button("Open...") {
                        model.openFilesFromDialog()
                    }
                    Button("Import from Clipboard") {
                        model.importFilesFromClipboard()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .help("Open files")

                Divider()
                    .frame(height: 16)

                Button("Merge All") {
                    model.mergeAllWindows()
                }
                .disabled(!model.canMergeAll)
                .help("Combine all windows into one tabbed window")
                .font(.caption)

                Button("Separate All") {
                    model.separateAllWindows()
                }
                .disabled(!model.canSeparateAll)
                .help("Split all tabs into separate windows")
                .font(.caption)

                Spacer()

                Button("Show in Finder") {
                    if let file = selectedFile {
                        NSWorkspace.shared.selectFile(file.filePath, inFileViewerRootedAtPath: file.folderPath)
                    }
                }
                .disabled(selectedFile == nil)
                .font(.caption)

                Button("Activate") {
                    if let file = selectedFile {
                        model.activateFile(file)
                    }
                }
                .disabled(selectedFile == nil)
                .keyboardShortcut(.return, modifiers: [])
                .font(.caption)
            }
            .padding(8)
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(WindowAccessor(alwaysOnTop: alwaysOnTop))
    }
}

// MARK: - Window Accessor for Always On Top

struct WindowAccessor: NSViewRepresentable {
    let alwaysOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            updateWindowLevel(for: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            updateWindowLevel(for: nsView)
        }
    }

    private func updateWindowLevel(for view: NSView) {
        guard let window = view.window else { return }
        window.level = alwaysOnTop ? .floating : .normal
        window.tabbingMode = .disallowed
    }
}

// MARK: - Window Group Header

struct WindowGroupHeaderView: View {
    let group: WindowGroupInfo
    let onRename: (String?) -> Void

    @State private var isEditing = false
    @State private var editingName = ""

    var body: some View {
        HStack {
            Image(systemName: group.isKeyWindow ? "macwindow.badge.plus" : "macwindow")
                .foregroundColor(group.isKeyWindow ? .accentColor : .secondary)

            if isEditing {
                TextField("Group name", text: $editingName, onCommit: {
                    finishEditing()
                })
                .textFieldStyle(.plain)
                .font(.system(.body, weight: group.isKeyWindow ? .semibold : .regular))
                .onExitCommand {
                    isEditing = false
                }
            } else {
                Text(group.displayName)
                    .font(.system(.body, weight: group.isKeyWindow ? .semibold : .regular))
                    .onTapGesture(count: 2) {
                        startEditing()
                    }
            }

            if group.isKeyWindow && !isEditing {
                Text("Active")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }

            Spacer()

            Text("\(group.tabCount)")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Rename Group...") {
                startEditing()
            }
            if group.customName != nil {
                Button("Reset Name") {
                    onRename(nil)
                }
            }
        }
    }

    private func startEditing() {
        editingName = group.customName ?? ""
        isEditing = true
    }

    private func finishEditing() {
        isEditing = false
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        onRename(trimmed.isEmpty ? nil : trimmed)
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let file: OpenFileInfo
    var showTabIndex: Bool = false
    var isActive: Bool = false
    var isDimmed: Bool = false
    var isDuplicate: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                if showTabIndex {
                    Text("\(file.tabIndex + 1)")
                        .font(.caption2)
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.secondary.opacity(isDimmed ? 0.3 : 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                Image(systemName: fileIcon)
                    .foregroundColor(isActive ? .white : (isDuplicate ? .orange : (isDimmed ? .secondary.opacity(0.5) : .accentColor)))
                Text(file.fileName)
                    .font(.system(.body, design: .default, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? .white : (isDimmed ? .secondary : .primary))
                if isDuplicate {
                    Text("(duplicate)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                Spacer()
                if isActive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundColor(.white)
                }
                Text("\(file.lineCount) lines")
                    .font(.caption)
                    .foregroundColor(isActive ? .white.opacity(0.8) : .secondary.opacity(isDimmed ? 0.5 : 1.0))
            }

            Text(file.filePath)
                .font(.caption)
                .foregroundColor(isActive ? .white.opacity(0.7) : .secondary.opacity(isDimmed ? 0.5 : 1.0))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Text(file.fileSize)
                Text("-")
                Text(file.modifiedAgo)
            }
            .font(.caption2)
            .foregroundColor(isActive ? .white.opacity(0.6) : .secondary.opacity(isDimmed ? 0.4 : 1.0))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, isActive ? 8 : 0)
        .background(isActive ? Color.accentColor.opacity(0.8) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(isDimmed ? 0.5 : 1.0)
    }

    private var fileIcon: String {
        let ext = file.fileName.split(separator: ".").last.map(String.init)?.lowercased() ?? ""
        switch ext {
        case "ipynb": return isDuplicate ? "doc.on.doc" : "doc.richtext"
        case "txt": return isDuplicate ? "doc.on.doc" : "doc.text.below.ecg"
        default: return isDuplicate ? "doc.on.doc" : "doc.text"
        }
    }
}
