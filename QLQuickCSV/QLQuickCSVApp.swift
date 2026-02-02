//
//  QLQuickCSVApp.swift
//  QLQuickCSV
//
//  Quick Look extension for CSV and TSV files
//  Features: Document viewer, Settings
//  Supports tabbed windows and keyboard shortcuts
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Main App

@main
struct QLQuickCSVApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    // Calculate default window size based on screen dimensions
    private var defaultWindowWidth: CGFloat {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return min(1800, max(800, screen.width * 0.85))
    }

    private var defaultWindowHeight: CGFloat {
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return screen.height * 0.9
    }

    var body: some Scene {
        // Document-based interface for opening CSV files
        DocumentGroup(viewing: CSVDocument.self) { file in
            CSVDocumentView(document: file.$document, fileURL: file.fileURL)
        }
        .commands {
            // File menu commands
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    // Viewing-only app, no new documents
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(true)

                Divider()

                Button("Open...") {
                    NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            // Settings command
            CommandGroup(after: .appSettings) {
                Button("About & Settings...") {
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: .command)
            }

            // View/Zoom commands
            CommandGroup(after: .toolbar) {
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .zoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshDocument, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            // Window/Tab navigation commands
            CommandGroup(after: .windowArrangement) {
                Button("Open Files Navigator") {
                    openWindow(id: "openFiles")
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Divider()

                Button("Select Next Tab") {
                    NSApp.keyWindow?.selectNextTab(nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])

                Button("Select Previous Tab") {
                    NSApp.keyWindow?.selectPreviousTab(nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])

                Divider()

                // Cmd+1 through Cmd+9 for direct tab access
                ForEach(1...9, id: \.self) { index in
                    Button("Select Tab \(index)") {
                        selectTab(at: index - 1)
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
                }
            }
        }
        .defaultSize(width: defaultWindowWidth, height: defaultWindowHeight)

        // Settings/About window
        Window("QLQuickCSV", id: "settings") {
            ContentView()
        }
        .defaultSize(width: 580, height: 780)
        .windowResizability(.contentSize)

        // Open Files Navigator window
        Window("Open Files", id: "openFiles") {
            OpenFilesNavigatorView()
        }
        .defaultSize(width: 450, height: 500)
        .windowResizability(.contentMinSize)
    }

    private func selectTab(at index: Int) {
        guard let window = NSApp.keyWindow,
              let tabGroup = window.tabGroup,
              index < tabGroup.windows.count else { return }
        tabGroup.windows[index].makeKeyAndOrderFront(nil)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App launched
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
