import Foundation

// MARK: - Models

struct GitFileChange: Identifiable {
    let id = UUID()
    let fileName:     String
    let filePath:     String
    let commitCount:  Int
    let lastModified: Date?
    let authors:      [String]

    enum Hotspot: String, CaseIterable {
        case cold    = "안정"
        case warm    = "보통"
        case hot     = "활발"
        case veryHot = "핫스팟"

        var icon: String {
            switch self {
            case .cold:    return "snowflake"
            case .warm:    return "thermometer.medium"
            case .hot:     return "flame"
            case .veryHot: return "flame.fill"
            }
        }
    }

    var hotspot: Hotspot {
        switch commitCount {
        case ..<5:    return .cold
        case 5..<15:  return .warm
        case 15..<30: return .hot
        default:      return .veryHot
        }
    }
}

struct GitHistoryReport {
    let isGitRepo:    Bool
    let totalCommits: Int
    let fileChanges:  [GitFileChange]
    let topAuthors:   [String]
}

// MARK: - Analyzer

struct GitHistoryAnalyzer {

    func analyze(projectPath: String, files: [FileAnalysis]) -> GitHistoryReport {
        guard let gitRoot = findGitRoot(from: projectPath) else {
            return GitHistoryReport(isGitRepo: false, totalCommits: 0, fileChanges: [], topAuthors: [])
        }

        let totalCommits = gitInt(["rev-list", "--count", "HEAD"], at: gitRoot)

        // Top authors (one git call)
        let allAuthors = gitLines(["log", "--format=%an"], at: gitRoot)
        let authorCounts = allAuthors.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        let topAuthors = authorCounts.sorted { $0.value > $1.value }.prefix(5).map(\.key)

        // File change counts — single efficient call: git log --name-only --format=""
        let rawLog = run(["log", "--name-only", "--format="], at: gitRoot)
        var commitCountMap = [String: Int]()
        for line in rawLog.components(separatedBy: "\n") where !line.isEmpty {
            commitCountMap[line, default: 0] += 1
        }

        // Per-file last-modified date (parallel using DispatchGroup would be ideal,
        // but keep simple with sequential — capped to top 50 files)
        let swiftFiles = files.filter { $0.fileName.hasSuffix(".swift") }

        let changes: [GitFileChange] = swiftFiles.compactMap { file in
            let rel = relativePath(file.filePath, to: gitRoot)
            let count = commitCountMap[rel] ?? commitCountMap[file.fileName] ?? 0
            guard count > 0 else { return nil }

            let dateStr = gitStr(["log", "-1", "--format=%ci", "--", rel], at: gitRoot)
            let date    = parseDate(dateStr)
            let authors = Array(Set(gitLines(["log", "--format=%an", "--", rel], at: gitRoot)))
                .sorted().prefix(3).map { $0 }

            return GitFileChange(
                fileName:     file.fileName,
                filePath:     file.filePath,
                commitCount:  count,
                lastModified: date,
                authors:      authors
            )
        }.sorted { $0.commitCount > $1.commitCount }

        return GitHistoryReport(
            isGitRepo:    true,
            totalCommits: totalCommits,
            fileChanges:  changes,
            topAuthors:   topAuthors
        )
    }

    // MARK: - Helpers

    private func findGitRoot(from path: String) -> String? {
        var url = URL(fileURLWithPath: path)
        for _ in 0 ..< 10 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.path
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    private func relativePath(_ full: String, to root: String) -> String {
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return full.hasPrefix(prefix) ? String(full.dropFirst(prefix.count)) : full
    }

    private func run(_ args: [String], at path: String) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()
        try? p.run(); p.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func gitStr(_ args: [String], at path: String) -> String {
        run(args, at: path).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func gitInt(_ args: [String], at path: String) -> Int {
        let s = gitStr(args, at: path)
        if s.contains("\n") { return s.components(separatedBy: "\n").filter { !$0.isEmpty }.count }
        return Int(s) ?? 0
    }

    private func gitLines(_ args: [String], at path: String) -> [String] {
        run(args, at: path).components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    private func parseDate(_ str: String) -> Date? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return fmt.date(from: str)
    }
}
