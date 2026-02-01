//
//  GitHelper.swift
//  QLQuickCSV
//
//  Detects git repository info by reading .git/config directly (no git commands needed)
//

import Foundation

struct GitInfo {
    let repoRoot: String
    let remoteName: String
    let remoteURL: String
    let branch: String
    let relativePath: String
    let githubURL: String?      // blob URL for viewing file
}

enum GitHelper {

    /// Get git information for a file by reading .git config files directly
    /// This approach is faster and more sandbox-friendly than running git commands
    static func getGitInfo(for filePath: String) -> GitInfo? {
        let fileURL = URL(fileURLWithPath: filePath)

        // Find the .git directory by walking up the tree
        guard let gitDir = findGitDirectory(from: fileURL.deletingLastPathComponent()) else {
            return nil
        }

        let repoRoot = gitDir.deletingLastPathComponent().path

        // Read remote URL from .git/config
        let configURL = gitDir.appendingPathComponent("config")
        guard let remoteURL = parseRemoteURL(from: configURL) else {
            return nil
        }

        // Read current branch from .git/HEAD
        let headURL = gitDir.appendingPathComponent("HEAD")
        let branch = parseCurrentBranch(from: headURL) ?? "main"

        // Get relative path from repo root
        let relativePath = String(filePath.dropFirst(repoRoot.count + 1))

        // Construct GitHub URLs (blob for viewing)
        let githubURL = constructGitHubURL(remoteURL: remoteURL, branch: branch, relativePath: relativePath)

        return GitInfo(
            repoRoot: repoRoot,
            remoteName: "origin",
            remoteURL: remoteURL,
            branch: branch,
            relativePath: relativePath,
            githubURL: githubURL
        )
    }

    /// Find .git directory by walking up the directory tree
    private static func findGitDirectory(from directory: URL) -> URL? {
        var current = directory
        let fileManager = FileManager.default

        while current.path != "/" {
            let gitDir = current.appendingPathComponent(".git")

            // Check if .git exists
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: gitDir.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Regular .git directory
                    return gitDir
                } else {
                    // .git file (worktree) - read the path from it
                    // Format: "gitdir: /path/to/actual/.git/worktrees/name"
                    if let content = try? String(contentsOf: gitDir, encoding: .utf8),
                       content.hasPrefix("gitdir: ") {
                        let path = content.dropFirst(8).trimmingCharacters(in: .whitespacesAndNewlines)
                        return URL(fileURLWithPath: path)
                    }
                }
            }

            current = current.deletingLastPathComponent()
        }

        return nil
    }

    /// Parse remote URL from .git/config
    /// Looks for [remote "origin"] section and extracts url = value
    private static func parseRemoteURL(from configURL: URL) -> String? {
        guard let content = try? String(contentsOf: configURL, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: .newlines)
        var inOriginSection = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Check for section headers
            if trimmed.hasPrefix("[") {
                inOriginSection = trimmed.lowercased().contains("[remote \"origin\"]")
                continue
            }

            // If in origin section, look for url =
            if inOriginSection && trimmed.lowercased().hasPrefix("url") {
                if let equalIndex = trimmed.firstIndex(of: "=") {
                    let url = trimmed[trimmed.index(after: equalIndex)...]
                        .trimmingCharacters(in: .whitespaces)
                    return url
                }
            }
        }

        return nil
    }

    /// Parse current branch from .git/HEAD
    /// Format: "ref: refs/heads/branch-name" or a commit SHA for detached HEAD
    private static func parseCurrentBranch(from headURL: URL) -> String? {
        guard let content = try? String(contentsOf: headURL, encoding: .utf8) else {
            return nil
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's a symbolic ref (normal branch)
        if trimmed.hasPrefix("ref: refs/heads/") {
            return String(trimmed.dropFirst(16)) // "ref: refs/heads/" is 16 chars
        }

        // Detached HEAD - return nil to use default "main"
        return nil
    }

    /// Construct GitHub URL from remote URL
    /// Supports both github.com and GitHub Enterprise instances
    private static func constructGitHubURL(remoteURL: String, branch: String, relativePath: String) -> String? {
        var url = remoteURL

        // Check if this is a GitHub repo (github.com or GitHub Enterprise)
        // Look for "github" anywhere in the URL (case-insensitive)
        guard url.lowercased().contains("github") else {
            return nil // Not a GitHub repo
        }

        // Handle SSH format: git@<host>:owner/repo.git
        if url.hasPrefix("git@") {
            let withoutPrefix = String(url.dropFirst(4)) // Remove "git@"
            if let colonIndex = withoutPrefix.firstIndex(of: ":") {
                let host = String(withoutPrefix[..<colonIndex])
                let path = String(withoutPrefix[withoutPrefix.index(after: colonIndex)...])
                url = "https://\(host)/\(path)"
            }
        }

        // Remove .git suffix if present
        if url.hasSuffix(".git") {
            url = String(url.dropLast(4))
        }

        // Construct URL
        let encodedPath = relativePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? relativePath

        return "\(url)/blob/\(branch)/\(encodedPath)"
    }
}
