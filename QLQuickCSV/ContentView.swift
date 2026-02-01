//
//  ContentView.swift
//  QLQuickCSV
//
//  Host app UI - displays installation instructions and settings
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            // Rich gradient background
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Custom tab bar
                HStack(spacing: 8) {
                    TabButton(title: "About", icon: "info.circle", isSelected: selectedTab == 0) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 0 }
                    }
                    TabButton(title: "Settings", icon: "gearshape", isSelected: selectedTab == 1) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedTab = 1 }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(.black.opacity(0.2))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                // Content
                Group {
                    if selectedTab == 0 {
                        AboutTab()
                    } else {
                        SettingsTab()
                    }
                }
                .padding(24)

                // Version footer
                Text("Version 1.0")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.bottom, 12)
            }
        }
        .frame(minWidth: 580, minHeight: 720)
    }

    private var backgroundGradient: some View {
        ZStack {
            // Base gradient - teal/green theme for CSV
            LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.15, blue: 0.2),
                    Color(red: 0.1, green: 0.2, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Accent orbs
            Circle()
                .fill(Color.teal.opacity(0.15))
                .frame(width: 300, height: 300)
                .blur(radius: 80)
                .offset(x: -100, y: -150)

            Circle()
                .fill(Color.green.opacity(0.12))
                .frame(width: 250, height: 250)
                .blur(radius: 70)
                .offset(x: 120, y: 100)

            Circle()
                .fill(Color.cyan.opacity(0.08))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: -80, y: 180)
        }
    }
}

// MARK: - Custom Tab Button

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                if isSelected {
                    Capsule()
                        .fill(.white.opacity(0.15))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - About Tab

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 28) {
            // App icon
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.teal.opacity(0.4), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                // Icon
                Image(systemName: "tablecells")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(28)
                    .background {
                        Circle()
                            .fill(.white.opacity(0.1))
                            .overlay {
                                Circle()
                                    .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                            }
                    }
            }

            // Title
            VStack(spacing: 8) {
                Text("CSV Quick Look")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Preview CSV and TSV files in Finder")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.6))
            }

            // Features card
            VStack(alignment: .leading, spacing: 12) {
                Label("Features", systemImage: "star.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))

                VStack(alignment: .leading, spacing: 6) {
                    featureRow("Interactive table with sorting & filtering")
                    featureRow("Column type detection (text, number, date)")
                    featureRow("Column statistics & distinct value counts")
                    featureRow("Multiple views: Table, Markdown, JSON")
                    featureRow("Search across all data (⌘F)")
                    featureRow("Copy as CSV, Markdown, JSON, or SQL")
                    featureRow("Dark/light mode support")
                    featureRow("GitHub URL integration")
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }
            }

            // Status card
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 18))
                    Text("Extension Ready")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Divider()
                    .background(.white.opacity(0.2))

                VStack(alignment: .leading, spacing: 10) {
                    Text("Enable in System Settings:")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8))

                    VStack(alignment: .leading, spacing: 6) {
                        instructionRow(icon: "gearshape", text: "System Settings")
                        instructionRow(icon: "lock.shield", text: "Privacy & Security → Extensions")
                        instructionRow(icon: "eye", text: "Quick Look")
                        instructionRow(icon: "checkmark.square", text: "Enable \"CSV QL Extension\"")
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }
            }

            // Quick actions
            HStack(spacing: 12) {
                Button {
                    openCSVFile()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.badge.plus")
                        Text("Open CSV File")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.teal.opacity(0.6))
                    }
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private func instructionRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private func featureRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.green.opacity(0.8))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func openCSVFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.csv, .tsv, .commaSeparatedText, .tabSeparatedText]
        panel.title = "Open CSV File"

        if panel.runModal() == .OK {
            for url in panel.urls {
                NSDocumentController.shared.openDocument(
                    withContentsOf: url,
                    display: true
                ) { _, _, _ in }
            }
        }
    }
}

// MARK: - Settings Tab

struct SettingsTab: View {
    @State private var themeMode: ThemeMode = Settings.shared.themeMode
    @State private var showRowNumbers: Bool = Settings.shared.showRowNumbers
    @State private var showTypeBadges: Bool = Settings.shared.showTypeBadges
    @State private var maxDisplayRows: Int = Settings.shared.maxDisplayRows
    @State private var autoDetectHeaders: Bool = Settings.shared.autoDetectHeaders

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.8))

                    Text("Settings")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.top, 8)

                // Display Settings card
                VStack(alignment: .leading, spacing: 20) {
                    // Theme Mode
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Appearance", systemImage: "circle.lefthalf.filled")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.8))

                        Picker("", selection: $themeMode) {
                            ForEach(ThemeMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: themeMode) { newValue in
                            Settings.shared.themeMode = newValue
                        }
                    }

                    Divider()
                        .background(.white.opacity(0.2))

                    // Toggle options
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Show row numbers", isOn: $showRowNumbers)
                            .onChange(of: showRowNumbers) { newValue in
                                Settings.shared.showRowNumbers = newValue
                            }

                        Toggle("Show column type badges", isOn: $showTypeBadges)
                            .onChange(of: showTypeBadges) { newValue in
                                Settings.shared.showTypeBadges = newValue
                            }

                        Toggle("Auto-detect header row", isOn: $autoDetectHeaders)
                            .onChange(of: autoDetectHeaders) { newValue in
                                Settings.shared.autoDetectHeaders = newValue
                            }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.8))
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        }
                }

                // Performance Settings card
                VStack(alignment: .leading, spacing: 16) {
                    Label("Performance", systemImage: "gauge.with.needle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Maximum rows to display")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.6))

                        Picker("", selection: $maxDisplayRows) {
                            Text("500").tag(500)
                            Text("1,000").tag(1000)
                            Text("5,000").tag(5000)
                            Text("10,000").tag(10000)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: maxDisplayRows) { newValue in
                            Settings.shared.maxDisplayRows = newValue
                        }

                        Text("Larger values may slow down previews for big files")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(24)
                .frame(maxWidth: 360)
                .background {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.white.opacity(0.08))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        }
                }

                Text("Changes apply on next Quick Look preview")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()
            }
        }
    }
}

#Preview {
    ContentView()
}
