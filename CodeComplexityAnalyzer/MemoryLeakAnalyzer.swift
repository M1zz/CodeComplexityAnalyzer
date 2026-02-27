import Foundation

// MARK: - Model

struct MemoryLeakIssue: Identifiable {
    let id = UUID()
    let fileName:    String
    let filePath:    String
    let lineNumber:  Int
    let lineContent: String
    let issueType:   IssueType
    let severity:    Severity
    let description: String
    let suggestion:  String

    enum IssueType: String, CaseIterable {
        case strongClosure  = "강한 클로저 캡처"
        case strongDelegate = "강한 델리게이트"
        case timerCycle     = "Timer 리테인 사이클"
        case notification   = "NotificationCenter 미제거"

        var icon: String {
            switch self {
            case .strongClosure:  return "chevron.left.forwardslash.chevron.right"
            case .strongDelegate: return "link"
            case .timerCycle:     return "timer"
            case .notification:   return "bell.badge"
            }
        }
    }

    enum Severity: String, CaseIterable, Comparable {
        case high   = "높음"
        case medium = "중간"
        case low    = "낮음"

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            let order: [Severity] = [.high, .medium, .low]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }
}

// MARK: - Analyzer

struct MemoryLeakAnalyzer {

    func analyze(files: [FileAnalysis]) -> [MemoryLeakIssue] {
        files.flatMap { file -> [MemoryLeakIssue] in
            guard let content = try? String(
                contentsOf: URL(fileURLWithPath: file.filePath), encoding: .utf8
            ) else { return [] }
            let lines = content.components(separatedBy: .newlines)
            return detectClosureCaptures(lines: lines, file: file)
                 + detectStrongDelegates(lines: lines, file: file)
                 + detectTimerCycles(lines: lines, file: file)
                 + detectNotificationMismatch(lines: lines, file: file, content: content)
        }
    }

    // MARK: - 1. 이스케이핑 클로저 강한 캡처

    private let escapingKeywords: [String] = [
        "DispatchQueue.main.async",
        "DispatchQueue.global",
        ".asyncAfter(",
        "Task {",
        "Task.detached",
        "Task(priority",
        ".sink {",
        ".sink(receiveValue",
        ".sink(receiveCompletion",
        "URLSession.shared.dataTask",
        "URLSession.shared.data(",
    ]

    private func detectClosureCaptures(lines: [String], file: FileAnalysis) -> [MemoryLeakIssue] {
        var issues: [MemoryLeakIssue] = []

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("*") else { continue }

            let isEscaping = escapingKeywords.contains { line.contains($0) }
            guard isEscaping else { continue }
            guard !line.contains("[weak self]"), !line.contains("[unowned self]") else { continue }

            // 이후 최대 15줄에서 self 캡처 여부 확인
            let end   = min(i + 15, lines.count)
            let block = lines[i..<end].joined(separator: "\n")

            guard block.contains("self.") || block.contains("self,") else { continue }
            guard !block.contains("[weak self]"), !block.contains("[unowned self]") else { continue }

            issues.append(MemoryLeakIssue(
                fileName:    file.fileName,
                filePath:    file.filePath,
                lineNumber:  i + 1,
                lineContent: trimmed,
                issueType:   .strongClosure,
                severity:    .high,
                description: "이스케이핑 클로저에서 self를 강하게 캡처합니다. 리테인 사이클이 발생할 수 있습니다.",
                suggestion:  "클로저 캡처 리스트에 [weak self]를 추가하세요.\n예: { [weak self] in\n    guard let self else { return }\n    self.someMethod()\n}"
            ))
        }
        return issues
    }

    // MARK: - 2. 강한 delegate 선언

    private func detectStrongDelegates(lines: [String], file: FileAnalysis) -> [MemoryLeakIssue] {
        var issues: [MemoryLeakIssue] = []
        let pattern = #"\bvar\s+\w*[Dd]elegate\w*\s*:"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }
            guard !line.contains("weak ") else { continue }

            let range = NSRange(line.startIndex..., in: line)
            guard regex.firstMatch(in: line, range: range) != nil else { continue }

            let fixed = trimmed
                .replacingOccurrences(of: "var ", with: "weak var ", range: trimmed.range(of: "var "))
            issues.append(MemoryLeakIssue(
                fileName:    file.fileName,
                filePath:    file.filePath,
                lineNumber:  i + 1,
                lineContent: trimmed,
                issueType:   .strongDelegate,
                severity:    .medium,
                description: "delegate가 강한 참조(strong)로 선언되어 리테인 사이클의 원인이 될 수 있습니다.",
                suggestion:  "weak var 로 변경하세요:\n\(fixed)"
            ))
        }
        return issues
    }

    // MARK: - 3. Timer 리테인 사이클

    private func detectTimerCycles(lines: [String], file: FileAnalysis) -> [MemoryLeakIssue] {
        var issues: [MemoryLeakIssue] = []

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }
            guard line.contains("Timer.scheduledTimer") || line.contains("Timer(timeInterval") else { continue }

            let end   = min(i + 10, lines.count)
            let block = lines[i..<end].joined(separator: "\n")
            guard block.contains("self."), !block.contains("[weak self]") else { continue }

            issues.append(MemoryLeakIssue(
                fileName:    file.fileName,
                filePath:    file.filePath,
                lineNumber:  i + 1,
                lineContent: trimmed,
                issueType:   .timerCycle,
                severity:    .high,
                description: "Timer 콜백이 self를 강하게 참조합니다. Timer가 살아있는 동안 객체가 해제되지 않습니다.",
                suggestion:  "1. Timer 블록에 [weak self] 추가\n2. deinit에서 timer.invalidate() 호출\n\nTimer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in\n    guard let self else { return }\n    self.tick()\n}"
            ))
        }
        return issues
    }

    // MARK: - 4. NotificationCenter 옵저버 미제거

    private func detectNotificationMismatch(
        lines: [String], file: FileAnalysis, content: String
    ) -> [MemoryLeakIssue] {
        let addCount    = content.components(separatedBy: "addObserver").count - 1
        let removeCount = content.components(separatedBy: "removeObserver").count - 1

        guard addCount > removeCount, addCount > 0 else { return [] }

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard line.contains("addObserver"), !trimmed.hasPrefix("//") else { continue }
            return [MemoryLeakIssue(
                fileName:    file.fileName,
                filePath:    file.filePath,
                lineNumber:  i + 1,
                lineContent: trimmed,
                issueType:   .notification,
                severity:    .medium,
                description: "addObserver \(addCount)회, removeObserver \(removeCount)회: 옵저버가 올바르게 제거되지 않을 수 있습니다.",
                suggestion:  "deinit에 removeObserver를 추가하세요:\ndeinit {\n    NotificationCenter.default.removeObserver(self)\n}"
            )]
        }
        return []
    }
}
