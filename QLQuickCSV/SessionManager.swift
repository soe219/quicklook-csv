//
//  SessionManager.swift
//  QLQuickCSV
//
//  Handles saving and loading session state for the Open Files Navigator.
//  Persists window groups, custom names, and file display orders across app launches.
//

import Foundation
import AppKit

// MARK: - Session State Models

/// Represents the complete session state to be persisted
struct SessionState: Codable {
    let version: Int
    let windowGroups: [WindowGroupState]
    let lastSaved: Date

    static let currentVersion = 1

    init(windowGroups: [WindowGroupState]) {
        self.version = Self.currentVersion
        self.windowGroups = windowGroups
        self.lastSaved = Date()
    }
}

/// Represents a window group's state for persistence
struct WindowGroupState: Codable {
    let id: UUID
    let customName: String?
    let fileURLs: [URL]  // In display order

    init(id: UUID, customName: String?, fileURLs: [URL]) {
        self.id = id
        self.customName = customName
        self.fileURLs = fileURLs
    }
}

// MARK: - Session Manager

/// Singleton that manages session persistence
class SessionManager {
    static let shared = SessionManager()

    private let fileManager = FileManager.default
    private var autosaveTimer: Timer?
    private let autosaveInterval: TimeInterval = 30.0

    /// Directory for application support files
    private var applicationSupportURL: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("QLQuickCSV", isDirectory: true)
    }

    /// Path to the session file
    private var sessionFileURL: URL? {
        applicationSupportURL?.appendingPathComponent("session.json")
    }

    private init() {}

    // MARK: - Directory Management

    /// Ensures the Application Support directory exists
    private func ensureDirectoryExists() throws {
        guard let dirURL = applicationSupportURL else {
            throw SessionError.invalidPath
        }

        if !fileManager.fileExists(atPath: dirURL.path) {
            try fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Save Operations

    /// Saves the current session state
    /// - Parameter state: The session state to save
    func save(_ state: SessionState) {
        do {
            try ensureDirectoryExists()

            guard let fileURL = sessionFileURL else {
                throw SessionError.invalidPath
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(state)
            try data.write(to: fileURL, options: .atomic)

            #if DEBUG
            print("[SessionManager] Saved session with \(state.windowGroups.count) window groups")
            #endif
        } catch {
            print("[SessionManager] Failed to save session: \(error)")
        }
    }

    /// Builds a SessionState from the current OpenFilesModel state
    @MainActor
    func buildSessionState(from model: OpenFilesModel) -> SessionState {
        let windowStates = model.windowGroups.map { group -> WindowGroupState in
            WindowGroupState(
                id: group.stableId,
                customName: model.customGroupNames[group.stableId],
                fileURLs: group.files.map { $0.url }
            )
        }
        return SessionState(windowGroups: windowStates)
    }

    /// Convenience method to save from the model
    @MainActor
    func saveSession(from model: OpenFilesModel) {
        let state = buildSessionState(from: model)
        save(state)
    }

    // MARK: - Load Operations

    /// Loads the saved session state
    /// - Returns: The loaded session state, or nil if none exists or loading fails
    func load() -> SessionState? {
        guard let fileURL = sessionFileURL,
              fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            let state = try decoder.decode(SessionState.self, from: data)

            // Validate version
            guard state.version <= SessionState.currentVersion else {
                print("[SessionManager] Session file is from a newer version, ignoring")
                return nil
            }

            #if DEBUG
            print("[SessionManager] Loaded session with \(state.windowGroups.count) window groups")
            #endif

            return state
        } catch {
            print("[SessionManager] Failed to load session: \(error)")
            return nil
        }
    }

    // MARK: - Session Restoration

    /// Restores the session by reopening files in their window groups
    /// - Parameter state: The session state to restore
    /// - Parameter completion: Called when restoration is complete (may be called multiple times as windows open)
    func restore(_ state: SessionState, completion: ((Bool) -> Void)? = nil) {
        guard !state.windowGroups.isEmpty else {
            completion?(true)
            return
        }

        // Track which files couldn't be opened
        var missingFiles: [URL] = []
        var restoredGroupCount = 0
        let totalGroups = state.windowGroups.filter { !$0.fileURLs.isEmpty }.count

        for (groupIndex, group) in state.windowGroups.enumerated() {
            // Filter out files that no longer exist
            let existingFiles = group.fileURLs.filter { url in
                let exists = fileManager.fileExists(atPath: url.path)
                if !exists {
                    missingFiles.append(url)
                    print("[SessionManager] Skipping missing file: \(url.path)")
                }
                return exists
            }

            guard !existingFiles.isEmpty else { continue }

            // Open the first file normally (creates new window)
            let firstURL = existingFiles[0]

            // Delay each group slightly to avoid race conditions
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(groupIndex) * 0.3) {
                NSDocumentController.shared.openDocument(withContentsOf: firstURL, display: true) { document, _, error in
                    guard let document = document, error == nil else {
                        print("[SessionManager] Failed to open \(firstURL.path): \(error?.localizedDescription ?? "unknown error")")
                        return
                    }

                    guard let windowController = document.windowControllers.first,
                          let window = windowController.window else { return }

                    // Open remaining files as tabs in this window
                    for url in existingFiles.dropFirst() {
                        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { tabDoc, _, tabError in
                            guard let tabDoc = tabDoc, tabError == nil else { return }

                            tabDoc.makeWindowControllers()
                            if let tabWC = tabDoc.windowControllers.first,
                               let tabWindow = tabWC.window {
                                window.addTabbedWindow(tabWindow, ordered: .above)
                            }
                        }
                    }

                    restoredGroupCount += 1
                    if restoredGroupCount == totalGroups {
                        completion?(missingFiles.isEmpty)
                    }
                }
            }
        }

        // Handle case where all groups were empty
        if totalGroups == 0 {
            completion?(true)
        }
    }

    // MARK: - Autosave

    /// Starts the autosave timer
    @MainActor
    func startAutosave(model: OpenFilesModel) {
        stopAutosave()

        autosaveTimer = Timer.scheduledTimer(withTimeInterval: autosaveInterval, repeats: true) { [weak self, weak model] _ in
            guard let self = self, let model = model else { return }
            Task { @MainActor in
                self.saveSession(from: model)
            }
        }
    }

    /// Stops the autosave timer
    func stopAutosave() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }

    // MARK: - Cleanup

    /// Deletes the session file
    func clearSession() {
        guard let fileURL = sessionFileURL else { return }
        try? fileManager.removeItem(at: fileURL)
    }

    // MARK: - Legacy Support

    /// Record a file being opened (legacy API for AppDelegate)
    func fileOpened(url: URL) {
        // This is now handled automatically by the model
        // Kept for backward compatibility
    }
}

// MARK: - Errors

enum SessionError: Error {
    case invalidPath
    case encodingFailed
    case decodingFailed
}
