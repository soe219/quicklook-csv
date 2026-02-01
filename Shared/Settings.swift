//
//  Settings.swift
//  QLQuickCSV
//
//  Shared settings between host app and Quick Look extension
//  Uses CFPreferences for cross-process communication
//

import Foundation

/// Theme mode selection
enum ThemeMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Settings manager for cross-process sharing
/// Uses CFPreferences which writes to the user's preferences domain.
/// The extension tries to read from the host app's sandboxed preferences file.
final class Settings {
    static let shared = Settings()

    // Shared application ID for CFPreferences
    private let appID = "com.qlcsv.shared" as CFString

    private init() {}

    /// Get the host app's preferences file URL (lazy to avoid initialization issues)
    private var hostAppPrefsURL: URL? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        return homeDir.appendingPathComponent(
            "Library/Containers/com.qlcsv.QLQuickCSV/Data/Library/Preferences/com.qlcsv.shared.plist"
        )
    }

    /// Check if running in extension context
    private var isExtension: Bool {
        Bundle.main.bundleIdentifier?.contains("CSVQLExtension") ?? false
    }

    private func loadHostAppSettings() -> [String: Any] {
        guard let url = hostAppPrefsURL,
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func getString(forKey key: String) -> String? {
        if isExtension {
            // Extension: try to read from host app's preferences file
            return loadHostAppSettings()[key] as? String
        } else {
            // Host app: use CFPreferences
            return CFPreferencesCopyAppValue(key as CFString, appID) as? String
        }
    }

    private func getBool(forKey key: String) -> Bool? {
        if isExtension {
            return loadHostAppSettings()[key] as? Bool
        } else {
            return CFPreferencesCopyAppValue(key as CFString, appID) as? Bool
        }
    }

    private func getInt(forKey key: String) -> Int? {
        if isExtension {
            return loadHostAppSettings()[key] as? Int
        } else {
            return CFPreferencesCopyAppValue(key as CFString, appID) as? Int
        }
    }

    private func setString(_ value: String, forKey key: String) {
        // Only host app should write settings
        guard !isExtension else { return }

        CFPreferencesSetAppValue(key as CFString, value as CFString, appID)
        CFPreferencesAppSynchronize(appID)
    }

    private func setBool(_ value: Bool, forKey key: String) {
        guard !isExtension else { return }

        CFPreferencesSetAppValue(key as CFString, value as CFNumber, appID)
        CFPreferencesAppSynchronize(appID)
    }

    private func setInt(_ value: Int, forKey key: String) {
        guard !isExtension else { return }

        CFPreferencesSetAppValue(key as CFString, value as CFNumber, appID)
        CFPreferencesAppSynchronize(appID)
    }

    // MARK: - Settings Properties

    /// Theme mode (system/light/dark)
    var themeMode: ThemeMode {
        get {
            guard let value = getString(forKey: "themeMode"),
                  let mode = ThemeMode(rawValue: value) else {
                return .system
            }
            return mode
        }
        set {
            setString(newValue.rawValue, forKey: "themeMode")
        }
    }

    /// Show row numbers in table view
    var showRowNumbers: Bool {
        get {
            getBool(forKey: "showRowNumbers") ?? true
        }
        set {
            setBool(newValue, forKey: "showRowNumbers")
        }
    }

    /// Maximum rows to display (for performance)
    var maxDisplayRows: Int {
        get {
            getInt(forKey: "maxDisplayRows") ?? 1000
        }
        set {
            setInt(newValue, forKey: "maxDisplayRows")
        }
    }

    /// Auto-detect headers in CSV files
    var autoDetectHeaders: Bool {
        get {
            getBool(forKey: "autoDetectHeaders") ?? true
        }
        set {
            setBool(newValue, forKey: "autoDetectHeaders")
        }
    }

    /// Show type badges on column headers
    var showTypeBadges: Bool {
        get {
            getBool(forKey: "showTypeBadges") ?? true
        }
        set {
            setBool(newValue, forKey: "showTypeBadges")
        }
    }

    /// Default delimiter (empty = auto-detect)
    var defaultDelimiter: String {
        get {
            getString(forKey: "defaultDelimiter") ?? ""
        }
        set {
            setString(newValue, forKey: "defaultDelimiter")
        }
    }
}
