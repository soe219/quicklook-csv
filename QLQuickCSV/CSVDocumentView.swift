//
//  CSVDocumentView.swift
//  QLQuickCSV
//
//  Document view for rendering CSV files with interactive features
//  Uses WebKit to display HTML-rendered content (same as Quick Look extension)
//

import SwiftUI
import WebKit

/// SwiftUI view for displaying a CSV document
struct CSVDocumentView: View {
    @Binding var document: CSVDocument
    let fileURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Header bar with file info
            HStack {
                Image(systemName: "tablecells")
                    .foregroundStyle(.secondary)
                Text(fileURL?.lastPathComponent ?? "Untitled")
                    .font(.headline)
                Spacer()
                Text("\(document.data.totalRows.formatted()) rows × \(document.data.totalColumns) columns")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Web view with interactive table
            if document.data.headers.isEmpty {
                VStack {
                    Text("No data to display")
                        .foregroundStyle(.secondary)
                    Text("File: \(fileURL?.path ?? "none")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                CSVWebView(document: document, fileURL: fileURL)
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}

/// NSViewRepresentable wrapper for WKWebView with link handling
struct CSVWebView: NSViewRepresentable {
    let document: CSVDocument
    let fileURL: URL?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.setupNotificationObservers()
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML()
        let baseURL = fileURL?.deletingLastPathComponent()
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    private func generateHTML() -> String {
        // Get GitHub URL if available
        var githubURL: String? = nil
        if let path = fileURL?.path {
            if let gitInfo = GitHelper.getGitInfo(for: path) {
                githubURL = gitInfo.githubURL
            }
        }

        return HTMLGenerator.generate(
            data: document.data,
            fileName: fileURL?.lastPathComponent ?? "Untitled.csv",
            filePath: fileURL?.path,
            fileSize: document.fileSize,
            modificationDate: document.modificationDate,
            githubURL: githubURL,
            rawContent: document.rawContent,
            maxDisplayRows: Settings.shared.maxDisplayRows
        )
    }

    // MARK: - Coordinator

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: CSVWebView
        weak var webView: WKWebView?
        private var observers: [Any] = []
        private var currentZoom: CGFloat = 1.0

        init(parent: CSVWebView) {
            self.parent = parent
            super.init()
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func setupNotificationObservers() {
            let nc = NotificationCenter.default

            // Zoom In
            observers.append(nc.addObserver(forName: .zoomIn, object: nil, queue: .main) { [weak self] _ in
                self?.zoomIn()
            })

            // Zoom Out
            observers.append(nc.addObserver(forName: .zoomOut, object: nil, queue: .main) { [weak self] _ in
                self?.zoomOut()
            })

            // Zoom Reset
            observers.append(nc.addObserver(forName: .zoomReset, object: nil, queue: .main) { [weak self] _ in
                self?.zoomReset()
            })

            // Refresh
            observers.append(nc.addObserver(forName: .refreshDocument, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            })
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Handle clicks on links (not initial page load)
            if navigationAction.navigationType == .linkActivated {
                let scheme = url.scheme?.lowercased() ?? ""

                // Handle http/https links - open in browser
                if scheme == "http" || scheme == "https" {
                    NSWorkspace.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }

                // Handle file:// links to CSV files - open in this app
                if scheme == "file" {
                    let ext = url.pathExtension.lowercased()
                    if ["csv", "tsv"].contains(ext) {
                        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                        decisionHandler(.cancel)
                        return
                    }
                }

                // Other links - open with default handler
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        // MARK: - Zoom

        func zoomIn() {
            currentZoom = min(currentZoom + 0.1, 3.0)
            applyZoom()
        }

        func zoomOut() {
            currentZoom = max(currentZoom - 0.1, 0.5)
            applyZoom()
        }

        func zoomReset() {
            currentZoom = 1.0
            applyZoom()
        }

        private func applyZoom() {
            let js = "document.body.style.zoom = '\(currentZoom)';"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        func refresh() {
            // Re-read file from disk and regenerate HTML
            guard let fileURL = parent.fileURL else {
                webView?.reload()
                return
            }

            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                let data = CSVParser.parse(content, maxRows: Settings.shared.maxDisplayRows)

                // Get file attributes
                let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
                let fileSize = attributes?[.size] as? Int64
                let modificationDate = attributes?[.modificationDate] as? Date

                // Get GitHub URL if available
                var githubURL: String? = nil
                if let gitInfo = GitHelper.getGitInfo(for: fileURL.path) {
                    githubURL = gitInfo.githubURL
                }

                // Generate fresh HTML
                let html = HTMLGenerator.generate(
                    data: data,
                    fileName: fileURL.lastPathComponent,
                    filePath: fileURL.path,
                    fileSize: fileSize,
                    modificationDate: modificationDate,
                    githubURL: githubURL,
                    rawContent: content,
                    maxDisplayRows: Settings.shared.maxDisplayRows
                )

                let baseURL = fileURL.deletingLastPathComponent()
                webView?.loadHTMLString(html, baseURL: baseURL)
            } catch {
                // Fallback to simple reload if file read fails
                webView?.reload()
            }
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let zoomIn = Notification.Name("QLQuickCSVZoomIn")
    static let zoomOut = Notification.Name("QLQuickCSVZoomOut")
    static let zoomReset = Notification.Name("QLQuickCSVZoomReset")
    static let refreshDocument = Notification.Name("QLQuickCSVRefreshDocument")
}

// MARK: - Preview

#Preview {
    CSVDocumentView(
        document: .constant(CSVDocument()),
        fileURL: URL(fileURLWithPath: "/tmp/example.csv")
    )
}
