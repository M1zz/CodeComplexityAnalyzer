import Foundation

// MARK: - Model

struct PerformanceIssue: Identifiable {

    enum Category: String, CaseIterable {
        case rendering    = "렌더링"
        case concurrency  = "동시성"
        case algorithm    = "알고리즘"
        case initialization = "초기화 비용"
        case debug        = "디버그 코드"
    }

    enum Severity: Int, Comparable {
        case high = 0, medium = 1, low = 2
        static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }

        var label: String {
            switch self { case .high: return "긴급"; case .medium: return "경고"; case .low: return "정보" }
        }
        var colorName: String {
            switch self { case .high: return "red"; case .medium: return "orange"; case .low: return "blue" }
        }
    }

    let id       = UUID()
    let fileName : String
    let filePath : String
    let line     : Int
    let category : Category
    let severity : Severity
    let title    : String
    let detail   : String
    let suggestion: String
}

struct PerformanceReport {
    let issues: [PerformanceIssue]

    var score: Double {
        var penalty = 0.0
        for issue in issues {
            switch issue.severity {
            case .high:   penalty += 10
            case .medium: penalty += 4
            case .low:    penalty += 1
            }
        }
        return max(0, min(100, 100 - penalty))
    }

    var byCategory: [PerformanceIssue.Category: [PerformanceIssue]] {
        Dictionary(grouping: issues, by: { $0.category })
    }
}

// MARK: - Analyzer

struct PerformanceAnalyzer {

    func analyze(files: [FileAnalysis]) -> PerformanceReport {
        var issues: [PerformanceIssue] = []
        for file in files {
            guard let content = try? String(contentsOfFile: file.filePath, encoding: .utf8) else { continue }
            issues += analyzeFile(file: file, content: content)
        }
        // 파일×카테고리×타이틀 단위로 중복 제거 (같은 파일에서 동일 패턴이 여러 줄 나오면 한 번만)
        var seen = Set<String>()
        let deduplicated = issues.filter { issue in
            let key = "\(issue.filePath)|\(issue.category.rawValue)|\(issue.title)"
            return seen.insert(key).inserted
        }
        return PerformanceReport(issues: deduplicated.sorted { $0.severity < $1.severity })
    }

    // MARK: - Per-file Analysis

    private func analyzeFile(file: FileAnalysis, content: String) -> [PerformanceIssue] {
        let rawLines = content.components(separatedBy: "\n")
        var issues: [PerformanceIssue] = []

        var inBody     = false
        var bodyDepth  = 0
        var bodyStart  = 0
        var bodyLines  = 0

        for (i, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            let lineNum = i + 1

            // 주석 줄 스킵
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*") { continue }

            // ── SwiftUI body 범위 추적 ───────────────────────────────────────
            if !inBody && trimmed.hasPrefix("var body:") && trimmed.contains("some View") {
                inBody    = true
                bodyDepth = rawLine.filter { $0 == "{" }.count - rawLine.filter { $0 == "}" }.count
                bodyStart = lineNum
                bodyLines = 1
            } else if inBody {
                bodyDepth += rawLine.filter { $0 == "{" }.count - rawLine.filter { $0 == "}" }.count
                bodyLines += 1
                if bodyDepth <= 0 {
                    // body 종료: 길이 검사
                    if bodyLines > 100 {
                        issues.append(issue(file, bodyStart, .rendering,
                            sev: bodyLines > 180 ? .high : .medium,
                            title: "SwiftUI body가 너무 깁니다 (\(bodyLines)줄)",
                            detail: "body는 상태가 변경될 때마다 재실행됩니다. 길수록 SwiftUI 렌더러의 diff 비용이 커집니다.",
                            suggestion: "하위 뷰를 별도 private struct View로 추출해 부분 갱신이 되도록 하세요."
                        ))
                    }
                    inBody = false
                }
            }

            // ── 동시성 ───────────────────────────────────────────────────────

            if trimmed.contains("Thread.sleep") {
                issues.append(issue(file, lineNum, .concurrency, sev: .high,
                    title: "Thread.sleep으로 스레드 차단",
                    detail: "Thread.sleep은 스레드를 완전히 멈춥니다. 메인 스레드에서 호출하면 UI가 얼어붙습니다.",
                    suggestion: "Task.sleep(nanoseconds:) 또는 DispatchQueue.asyncAfter를 사용하세요."
                ))
            }

            if trimmed.contains("DispatchQueue.main.sync") {
                issues.append(issue(file, lineNum, .concurrency, sev: .high,
                    title: "DispatchQueue.main.sync — 데드락 위험",
                    detail: "메인 스레드에서 main.sync를 호출하면 데드락이 발생합니다.",
                    suggestion: "DispatchQueue.main.async를 사용하거나 @MainActor로 전환하세요."
                ))
            }

            if trimmed.contains("semaphore.wait()") || trimmed.hasSuffix(".wait()") {
                issues.append(issue(file, lineNum, .concurrency, sev: .medium,
                    title: "세마포어 wait() — 스레드 차단 가능성",
                    detail: "세마포어 wait()는 현재 스레드를 차단합니다. 메인 스레드에서 호출 시 UI가 응답하지 않습니다.",
                    suggestion: "async/await 패턴으로 전환하거나 background 큐에서만 사용하세요."
                ))
            }

            // ── 렌더링 ───────────────────────────────────────────────────────

            if inBody && (trimmed.contains(".sorted(") || trimmed.contains(".sorted {") || trimmed.contains(".sort(") || trimmed.contains(".sort {")) {
                issues.append(issue(file, lineNum, .rendering, sev: .medium,
                    title: "body에서 정렬 연산 수행",
                    detail: "body는 뷰가 갱신될 때마다 실행됩니다. 정렬 연산이 매 렌더링마다 반복됩니다.",
                    suggestion: "ViewModel에서 미리 정렬된 배열을 제공하거나, @State computed property로 캐시하세요."
                ))
            }

            if inBody && trimmed.contains("JSONDecoder") {
                issues.append(issue(file, lineNum, .rendering, sev: .high,
                    title: "body에서 JSON 디코딩",
                    detail: "JSON 디코딩은 무거운 연산입니다. 매 렌더링마다 실행되면 성능이 크게 저하됩니다.",
                    suggestion: "디코딩 로직을 ViewModel의 초기화 또는 async 메서드로 이동하세요."
                ))
            }

            if inBody && (trimmed.contains("URLSession") || trimmed.contains("dataTask")) {
                issues.append(issue(file, lineNum, .rendering, sev: .high,
                    title: "body에서 네트워크 요청",
                    detail: "뷰 body에서 직접 네트워크 호출을 하면 렌더링을 차단하고 중복 요청이 발생합니다.",
                    suggestion: ".task { } modifier나 .onAppear 내의 ViewModel 메서드를 통해 호출하세요."
                ))
            }

            // ── 초기화 비용 ──────────────────────────────────────────────────

            // DateFormatter / NumberFormatter를 매번 새로 생성하는 패턴
            // static let, lazy var 로 선언된 것은 제외
            let isStaticOrLazy = trimmed.hasPrefix("static") || trimmed.hasPrefix("lazy") || trimmed.contains("static let") || trimmed.contains("lazy var")

            if !isStaticOrLazy && trimmed.contains("DateFormatter()") {
                issues.append(issue(file, lineNum, .initialization, sev: .high,
                    title: "DateFormatter를 매번 새로 생성",
                    detail: "DateFormatter 초기화는 매우 비쌉니다. 메서드 내에서 반복 생성하면 성능이 크게 떨어집니다.",
                    suggestion: "static let shared = DateFormatter() 로 선언해 재사용하거나, DateFormatter.localizedString을 사용하세요."
                ))
            }

            if !isStaticOrLazy && trimmed.contains("NumberFormatter()") {
                issues.append(issue(file, lineNum, .initialization, sev: .medium,
                    title: "NumberFormatter를 매번 새로 생성",
                    detail: "NumberFormatter 초기화는 상당한 CPU 비용이 있습니다. 반복 생성 시 성능이 저하됩니다.",
                    suggestion: "static let으로 선언해 재사용하세요."
                ))
            }

            if !isStaticOrLazy && trimmed.contains("Calendar.current") && inBody {
                issues.append(issue(file, lineNum, .initialization, sev: .low,
                    title: "body에서 Calendar.current 반복 접근",
                    detail: "Calendar.current는 내부적으로 생성 비용이 있습니다. body 내에서 반복 접근하면 불필요한 연산이 발생합니다.",
                    suggestion: "let calendar = Calendar.current 를 body 외부에서 한 번만 가져오세요."
                ))
            }

            if trimmed.contains("try!") {
                issues.append(issue(file, lineNum, .initialization, sev: .medium,
                    title: "try! 강제 실행 — 크래시 위험",
                    detail: "에러가 발생하면 앱이 즉시 종료됩니다. 프로덕션 코드에서는 절대 사용하면 안 됩니다.",
                    suggestion: "do { try ... } catch { } 또는 try? 를 사용하세요."
                ))
            }

            // ── 알고리즘 ─────────────────────────────────────────────────────

            if trimmed.contains(".filter(") && trimmed.contains(".map(") {
                issues.append(issue(file, lineNum, .algorithm, sev: .low,
                    title: "filter + map 체인 — 배열 두 번 순회",
                    detail: "filter와 map을 연달아 사용하면 중간 배열이 생성되어 메모리와 CPU를 낭비합니다.",
                    suggestion: "compactMap { ... } 또는 lazy.filter(...).map(...)으로 단일 순회하세요."
                ))
            }

            // ── 디버그 코드 ──────────────────────────────────────────────────

            if !file.fileName.contains("Test") &&
               (trimmed.hasPrefix("print(") || (trimmed.contains(" print(") && !trimmed.contains("//")) ) {
                issues.append(issue(file, lineNum, .debug, sev: .low,
                    title: "print() 가 프로덕션 코드에 남아 있음",
                    detail: "print()는 릴리즈 빌드에서도 실행되며 I/O 비용을 유발합니다.",
                    suggestion: "#if DEBUG 블록으로 감싸거나 os_log / Logger를 사용하세요."
                ))
            }

            if trimmed.contains("NSLog(") {
                issues.append(issue(file, lineNum, .debug, sev: .medium,
                    title: "NSLog — 동기 I/O로 성능 저하",
                    detail: "NSLog는 동기적으로 실행되며 print보다 훨씬 느립니다. 메인 스레드에서 호출 시 UI가 버벅입니다.",
                    suggestion: "os_log 또는 Logger(subsystem:category:)를 사용하세요."
                ))
            }
        }

        // ── 중첩 for 루프 검사 (별도 패스) ─────────────────────────────────
        issues += checkNestedLoops(file: file, lines: rawLines)

        return issues
    }

    // MARK: - Nested Loop Detector

    private func checkNestedLoops(file: FileAnalysis, lines: [String]) -> [PerformanceIssue] {
        var result: [PerformanceIssue] = []
        var depth = 0
        var outerLine = 0

        for (i, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }

            let isFor    = trimmed.hasPrefix("for ") && trimmed.contains(" in ")
            let isWhile  = trimmed.hasPrefix("while ") || trimmed.hasPrefix("repeat {")

            if isFor || isWhile {
                depth += 1
                if depth == 1 { outerLine = i + 1 }
                if depth == 2 {
                    result.append(issue(file, outerLine, .algorithm, sev: .medium,
                        title: "중첩 반복문 — O(n²) 가능성",
                        detail: "중첩 for/while 루프는 데이터가 커질수록 성능이 제곱으로 저하됩니다.",
                        suggestion: "Dictionary 또는 Set으로 O(1) 조회를 사용하거나, 알고리즘을 단일 패스로 재설계하세요."
                    ))
                    depth = 0 // 한 번만 리포트
                }
            }

            let opens  = rawLine.filter { $0 == "{" }.count
            let closes = rawLine.filter { $0 == "}" }.count
            if closes > opens && depth > 0 {
                depth = max(0, depth - (closes - opens))
            }
        }
        return result
    }

    // MARK: - Factory

    private func issue(
        _ file: FileAnalysis, _ line: Int, _ category: PerformanceIssue.Category,
        sev: PerformanceIssue.Severity, title: String, detail: String, suggestion: String
    ) -> PerformanceIssue {
        PerformanceIssue(
            fileName:   file.fileName,
            filePath:   file.filePath,
            line:       line,
            category:   category,
            severity:   sev,
            title:      title,
            detail:     detail,
            suggestion: suggestion
        )
    }
}
