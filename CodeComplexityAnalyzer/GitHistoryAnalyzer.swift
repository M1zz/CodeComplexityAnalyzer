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

        // 단일 git log 호출로 커밋 수·날짜·작성자·변경파일 한 번에 수집
        // 형식: "COMMIT\t<날짜ISO>\t<작성자>" 줄 다음에 변경된 파일 목록
        let raw = run(
            ["log", "--format=COMMIT\t%ci\t%an", "--name-only", "--max-count=2000"],
            at: gitRoot,
            timeout: 15
        )

        var commitCountMap   = [String: Int]()
        var lastModifiedMap  = [String: Date]()
        var authorsMap       = [String: Set<String>]()
        var authorFreq       = [String: Int]()
        var totalCommits     = 0

        var currentDate: Date? = nil
        var currentAuthor = ""
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd HH:mm:ss Z"

        for line in raw.components(separatedBy: "\n") {
            if line.hasPrefix("COMMIT\t") {
                totalCommits += 1
                let parts = line.components(separatedBy: "\t")
                currentDate   = parts.count > 1 ? dateFmt.date(from: parts[1]) : nil
                currentAuthor = parts.count > 2 ? parts[2] : ""
                if !currentAuthor.isEmpty { authorFreq[currentAuthor, default: 0] += 1 }
            } else if !line.isEmpty {
                commitCountMap[line, default: 0] += 1
                if lastModifiedMap[line] == nil, let d = currentDate {
                    lastModifiedMap[line] = d   // 첫 출현 = 가장 최근 커밋
                }
                if !currentAuthor.isEmpty {
                    authorsMap[line, default: []].insert(currentAuthor)
                }
            }
        }

        let topAuthors = authorFreq.sorted { $0.value > $1.value }.prefix(5).map(\.key)
        let swiftFiles = files.filter { $0.fileName.hasSuffix(".swift") }

        let changes: [GitFileChange] = swiftFiles.compactMap { file in
            let rel   = relativePath(file.filePath, to: gitRoot)
            let count = commitCountMap[rel] ?? commitCountMap[file.fileName] ?? 0
            guard count > 0 else { return nil }
            return GitFileChange(
                fileName:     file.fileName,
                filePath:     file.filePath,
                commitCount:  count,
                lastModified: lastModifiedMap[rel] ?? lastModifiedMap[file.fileName],
                authors:      Array(authorsMap[rel] ?? authorsMap[file.fileName] ?? []).sorted().prefix(3).map { $0 }
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

    /// timeout(초) 초과 시 프로세스를 강제 종료하고 빈 문자열 반환
    private func run(_ args: [String], at path: String, timeout: TimeInterval = 30) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: path)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError  = Pipe()

        do { try p.run() } catch { return "" }

        let deadline = DispatchTime.now() + timeout
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }

        if done.wait(timeout: deadline) == .timedOut {
            p.terminate()
            return ""
        }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
