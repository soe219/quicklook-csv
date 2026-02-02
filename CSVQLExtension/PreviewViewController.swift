//
//  PreviewViewController.swift
//  CSVQLExtension
//
//  Quick Look preview controller for CSV and TSV files
//  Returns HTML-based data preview with interactive table features
//

import Cocoa
import Quartz
import CoreServices

/// PreviewViewController handles Quick Look previews for CSV files.
///
/// With `QLIsDataBasedPreview = true`, the system uses `providePreview(for:)`
/// which returns data (HTML) directly, bypassing view-based rendering.
class PreviewViewController: NSViewController, QLPreviewingController {

    // MARK: - Modern Data-Based Preview (macOS 12+)
    //
    // When QLIsDataBasedPreview is true in Info.plist, Quick Look calls this method
    // instead of instantiating the view controller's view hierarchy.
    // We return HTML data that Quick Look renders in its own WebView.

    @available(macOSApplicationExtension 12.0, *)
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        // Read the CSV file contents
        let fileURL = request.fileURL

        // Read raw file content for TXT view
        let rawContent = try? String(contentsOf: fileURL, encoding: .utf8)

        // Parse CSV
        guard let csvData = CSVParser.parse(contentsOf: fileURL, maxRows: Settings.shared.maxDisplayRows) else {
            throw NSError(
                domain: "CSVQLExtension",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse CSV file"]
            )
        }

        // Get file attributes for display in header
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileSize = attributes?[.size] as? Int64
        let modificationDate = attributes?[.modificationDate] as? Date

        // Get GitHub URL if file is in a GitHub repo
        let gitInfo = GitHelper.getGitInfo(for: fileURL.path)

        // Generate HTML preview
        let html = HTMLGenerator.generate(
            data: csvData,
            fileName: fileURL.lastPathComponent,
            filePath: fileURL.path,
            fileSize: fileSize,
            modificationDate: modificationDate,
            githubURL: gitInfo?.githubURL,
            rawContent: rawContent,
            maxDisplayRows: Settings.shared.maxDisplayRows
        )

        // Return HTML-based preview
        // contentSize is the preferred size hint for the Quick Look panel
        // Dynamically size based on screen dimensions for optimal viewing
        let screen = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1300, height: 1400)
        // Width: use 90% of screen width for data tables
        let previewWidth = min(2200, max(900, screen.width * 0.90))
        let reply = QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: previewWidth, height: screen.height)
        ) { replyToUpdate in
            replyToUpdate.stringEncoding = .utf8
            return html.data(using: .utf8)!
        }

        return reply
    }

    // MARK: - Legacy View-Based Preview (macOS 10.15-11)
    //
    // This method is called on older macOS versions when QLIsDataBasedPreview
    // is false or when running on pre-macOS 12 systems.

    override var nibName: NSNib.Name? {
        // Only needed for view-based previews
        return NSNib.Name("PreviewViewController")
    }

    override func loadView() {
        // Create a simple view for legacy support
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 272))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        // Legacy view-based preview
        // For full support, you would load content into a WebView here
        handler(nil)
    }
}
