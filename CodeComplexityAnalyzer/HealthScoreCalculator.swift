import Foundation

struct HealthScoreCalculator {

    // MARK: - Score Calculation

    func calculate(
        analyses: [FileAnalysis],
        edges: [DependencyEdge],
        leaks: [MemoryLeakIssue],
        qualityReport: CodeQualityReport?
    ) -> HealthScore {
        let complexityScore = calcComplexityScore(analyses: analyses)
        let dependencyScore = calcDependencyScore(analyses: analyses, edges: edges)
        let memoryScore     = calcMemoryScore(leaks: leaks)
        let qualityScore    = qualityReport?.overallScore ?? 80.0

        // 가중치: 복잡도 30% + 의존성 20% + 메모리 25% + 품질 25%
        let overall = complexityScore * 0.30
                    + dependencyScore * 0.20
                    + memoryScore     * 0.25
                    + qualityScore    * 0.25

        return HealthScore(
            overall:              max(0, min(100, overall)),
            complexityComponent:  complexityScore,
            dependencyComponent:  dependencyScore,
            memoryComponent:      memoryScore,
            qualityComponent:     qualityScore
        )
    }

    // MARK: - Action Generation

    func generateActions(
        analyses: [FileAnalysis],
        edges: [DependencyEdge],
        leaks: [MemoryLeakIssue],
        archReport: ArchReport?,
        qualityReport: CodeQualityReport?,
        functions: [FunctionInfo]
    ) -> [ActionItem] {
        var actions: [ActionItem] = []

        // 1. 50줄 초과 함수 (상위 5개)
        let longFunctions = functions
            .filter { $0.lineCount > 50 }
            .sorted { $0.lineCount > $1.lineCount }
            .prefix(5)
        for fn in longFunctions {
            actions.append(ActionItem(
                title:       "\(fn.fileName)의 '\(fn.name)' 함수가 너무 깁니다",
                detail:      "\(fn.lineCount)줄짜리 함수는 이해하기 어렵습니다. 작은 함수 여러 개로 쪼개면 버그를 찾기 쉬워집니다.",
                fileName:    fn.fileName,
                filePath:    fn.filePath,
                category:    .complexity,
                severity:    fn.lineCount > 100 ? .critical : .warning,
                impactScore: min(10, Double(fn.lineCount) / 20.0)
            ))
        }

        // 2. CC > 10 함수 (상위 5개)
        let highCCFunctions = functions
            .filter { $0.cc > 10 }
            .sorted { $0.cc > $1.cc }
            .prefix(5)
        for fn in highCCFunctions {
            actions.append(ActionItem(
                title:       "\(fn.fileName)의 '\(fn.name)' 함수가 너무 복잡합니다",
                detail:      "분기(if/for/switch)가 \(fn.cc)개나 있어 테스트하기 어렵습니다. 분기를 줄이거나 도우미 함수로 추출하세요.",
                fileName:    fn.fileName,
                filePath:    fn.filePath,
                category:    .complexity,
                severity:    fn.cc > 20 ? .critical : .warning,
                impactScore: min(10, Double(fn.cc) / 3.0)
            ))
        }

        // 3. 순환 의존성 파일
        let cyclicNodes = DependencyAnalyzer.findCyclicNodes(from: edges)
        let cyclicFiles = analyses
            .filter { cyclicNodes.contains($0.filePath) }
            .prefix(5)
        for file in cyclicFiles {
            actions.append(ActionItem(
                title:       "\(file.fileName)이 순환 의존성에 엮여 있습니다",
                detail:      "이 파일은 다른 파일과 서로 참조하고 있어, 한 쪽을 수정하면 다른 쪽도 영향 받습니다. 프로토콜로 의존성을 끊으세요.",
                fileName:    file.fileName,
                filePath:    file.filePath,
                category:    .dependency,
                severity:    .warning,
                impactScore: 5.0
            ))
        }

        // 4. high 심각도 메모리 이슈 (상위 5개)
        let highMemoryIssues = leaks
            .filter { $0.severity == .high }
            .prefix(5)
        for issue in highMemoryIssues {
            actions.append(ActionItem(
                title:       "\(issue.fileName): \(titleFor(issueType: issue.issueType))",
                detail:      issue.description + "\n\n수정 방법: " + issue.suggestion,
                fileName:    issue.fileName,
                filePath:    issue.filePath,
                category:    .memory,
                severity:    .critical,
                impactScore: 7.0
            ))
        }

        // 5. 품질 점수 낮은 파일 (상위 5개)
        if let quality = qualityReport {
            let poorFiles = quality.files
                .filter { $0.score < 60 }
                .prefix(5)
            for fq in poorFiles {
                let issuesSummary = fq.issues.joined(separator: ", ")
                actions.append(ActionItem(
                    title:       "\(fq.file.fileName) 코드 품질을 개선하세요",
                    detail:      "품질 점수: \(Int(fq.score))점. 문제: \(issuesSummary.isEmpty ? "전반적인 품질 개선 필요" : issuesSummary)",
                    fileName:    fq.file.fileName,
                    filePath:    fq.file.filePath,
                    category:    .quality,
                    severity:    fq.score < 30 ? .critical : .warning,
                    impactScore: (100 - fq.score) / 15.0
                ))
            }
        }

        // 6. high 아키텍처 이슈 (상위 3개)
        if let arch = archReport {
            let highArchIssues = arch.issues
                .filter { $0.severity == .high }
                .prefix(3)
            for issue in highArchIssues {
                actions.append(ActionItem(
                    title:       "\(issue.fileName): \(titleFor(archIssueType: issue.type))",
                    detail:      issue.description + "\n\n해결 방법: " + issue.suggestion,
                    fileName:    issue.fileName,
                    filePath:    issue.filePath,
                    category:    .architecture,
                    severity:    .warning,
                    impactScore: 6.0
                ))
            }
        }

        // severity 오름차순 → impactScore 내림차순 정렬, 최대 20개
        return Array(
            actions
                .sorted { lhs, rhs in
                    if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
                    return lhs.impactScore > rhs.impactScore
                }
                .prefix(20)
        )
    }

    // MARK: - Private Score Helpers

    private func calcComplexityScore(analyses: [FileAnalysis]) -> Double {
        var score = 100.0
        for analysis in analyses {
            switch analysis.complexityLevel {
            case .veryHigh: score -= 8
            case .high:     score -= 4
            case .medium:   score -= 1
            case .low:      break
            }
        }
        return max(0, min(100, score))
    }

    private func calcDependencyScore(analyses: [FileAnalysis], edges: [DependencyEdge]) -> Double {
        guard !analyses.isEmpty else { return 100.0 }
        let cyclicNodes  = DependencyAnalyzer.findCyclicNodes(from: edges)
        let cyclicRatio  = Double(cyclicNodes.count) / Double(analyses.count)
        return max(0, min(100, 100 - cyclicRatio * 60))
    }

    private func calcMemoryScore(leaks: [MemoryLeakIssue]) -> Double {
        var penalty = 0.0
        for leak in leaks {
            switch leak.severity {
            case .high:   penalty += 10
            case .medium: penalty += 4
            case .low:    penalty += 1
            }
        }
        return max(0, min(100, 100 - penalty))
    }

    // MARK: - Korean Title Helpers

    private func titleFor(issueType: MemoryLeakIssue.IssueType) -> String {
        switch issueType {
        case .strongClosure:  return "클로저가 self를 강하게 잡고 있어 메모리가 해제되지 않습니다"
        case .strongDelegate: return "delegate가 강한 참조로 선언되어 메모리 누수 위험이 있습니다"
        case .timerCycle:     return "Timer가 객체를 놓아주지 않아 메모리가 쌓입니다"
        case .notification:   return "알림 옵저버가 제거되지 않아 메모리가 누수됩니다"
        }
    }

    private func titleFor(archIssueType: ArchIssue.IssueType) -> String {
        switch archIssueType {
        case .massiveViewController: return "너무 많은 역할을 하는 파일입니다"
        case .godObject:             return "너무 많은 역할을 하는 클래스입니다"
        case .layerViolation:        return "레이어 간 경계를 위반하고 있습니다"
        case .singletonAbuse:        return "싱글턴 패턴이 남용되고 있습니다"
        case .namingMismatch:        return "파일 이름이 역할을 반영하지 않습니다"
        case .missingProtocol:       return "프로토콜이 없어 테스트와 교체가 어렵습니다"
        case .mixedConcerns:         return "여러 역할이 한 파일에 섞여 있습니다"
        }
    }
}
