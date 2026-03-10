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
        // struct/enum 파일은 값 타입 — retain cycle 불가
        guard file.classCount > 0 else { return [] }

        var issues: [MemoryLeakIssue] = []

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("*") else { continue }

            let isEscaping = escapingKeywords.contains { line.contains($0) }
            guard isEscaping else { continue }
            guard !line.contains("[weak self]"), !line.contains("[unowned self]") else { continue }

            // 앞쪽 30줄에 이미 [weak self]가 있고 아직 그 클로저 안에 있으면 외부에서 처리된 것
            let lookbackStart = max(0, i - 30)
            let lookback = lines[lookbackStart..<i].joined(separator: "\n")
            if lookback.contains("[weak self]") || lookback.contains("[unowned self]") {
                let opens  = lookback.filter { $0 == "{" }.count
                let closes = lookback.filter { $0 == "}" }.count
                if opens > closes { continue } // 외부 [weak self] 클로저 안에 있음
            }

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
        // 클래스가 없는 파일은 스킵
        guard file.classCount > 0 else { return [] }

        var issues: [MemoryLeakIssue] = []
        let pattern = #"\bvar\s+\w*[Dd]elegate\w*\s*:"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//") else { continue }
            guard !line.contains("weak ") else { continue }
            // protocol 선언 안의 delegate 프로퍼티는 스킵 (구현체가 아님)
            guard !trimmed.hasPrefix("var") || !line.contains("protocol ") else { continue }

            let range = NSRange(line.startIndex..., in: line)
            guard regex.firstMatch(in: line, range: range) != nil else { continue }

            // 앞쪽 20줄에서 현재 타입 컨텍스트 확인 — protocol 블록 내부면 스킵
            let lookback = lines[max(0, i - 20)..<i].joined(separator: "\n")
            if lookback.contains("protocol ") {
                let opens  = lookback.filter { $0 == "{" }.count
                let closes = lookback.filter { $0 == "}" }.count
                if opens > closes { continue }
            }

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
        // 셀렉터 방식 addObserver만 카운트 (토큰 방식은 removeObserver 불필요)
        // 토큰 방식: `let token = NotificationCenter.default.addObserver(forName:...)`
        // 셀렉터 방식: `NotificationCenter.default.addObserver(self, selector:...)`
        let selectorAddCount = lines.filter { line in
            line.contains("addObserver") &&
            (line.contains("selector:") || line.contains(", selector")) &&
            !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }.count

        // 토큰 방식 (결과를 변수에 저장하는 패턴)
        let tokenAddCount = lines.filter { line in
            line.contains("addObserver") &&
            !line.contains("selector:") &&
            (line.contains("= NotificationCenter") || line.contains("=NotificationCenter")) &&
            !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }.count

        let removeCount = content.components(separatedBy: "removeObserver").count - 1

        // 셀렉터 방식이 있고 removeObserver가 부족한 경우만 신고
        guard selectorAddCount > 0, selectorAddCount > removeCount else { return [] }

        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard line.contains("addObserver"), line.contains("selector:"),
                  !trimmed.hasPrefix("//") else { continue }
            return [MemoryLeakIssue(
                fileName:    file.fileName,
                filePath:    file.filePath,
                lineNumber:  i + 1,
                lineContent: trimmed,
                issueType:   .notification,
                severity:    .medium,
                description: "셀렉터 방식 addObserver \(selectorAddCount)회, removeObserver \(removeCount)회: 옵저버가 누적될 수 있습니다. (토큰 방식 \(tokenAddCount)건은 제외)",
                suggestion:  "deinit에 removeObserver를 추가하세요:\ndeinit {\n    NotificationCenter.default.removeObserver(self)\n}"
            )]
        }
        return []
    }
}
