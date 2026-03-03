import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case json     = "JSON"
    case csv      = "CSV"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .markdown: return "doc.text"
        case .json:     return "curlybraces"
        case .csv:      return "tablecells"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .json:     return "json"
        case .csv:      return "csv"
        }
    }

    var utType: UTType {
        switch self {
        case .markdown: return .plainText
        case .json:     return .json
        case .csv:      return .commaSeparatedText
        }
    }
}

// MARK: - ViewModel

@MainActor
class AnalyzerViewModel: ObservableObject {
    @Published var analyses:        [FileAnalysis]    = []
    @Published var summary:          ProjectSummary?
    @Published var dependencyEdges: [DependencyEdge]  = []
    @Published var leakIssues:      [MemoryLeakIssue] = []
    @Published var archReport:       ArchReport?
    @Published var functions:       [FunctionInfo]    = []
@Published var qualityReport:    CodeQualityReport?
    @Published var gitHistoryReport: GitHistoryReport?
    @Published var isAnalyzing = false
    @Published var selectedPath: String?
    @Published var healthScore: HealthScore?
    @Published var actionItems: [ActionItem] = []
    @Published var snapshots: [ProjectSnapshot] = []
    @Published var healthTrend: Double? = nil
    @Published var orphanedFiles: [FileAnalysis] = []

    private let analyzer = CodeAnalyzer()

    init() { loadSnapshots() }

    // MARK: - 폴더 선택

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "분석할 Xcode 프로젝트 폴더를 선택하세요"
        panel.prompt = "선택"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.selectedPath = url.path
                await self?.analyzeProject(at: url)
            }
        }
    }

    // MARK: - 분석

    func analyzeProject(at url: URL) async {
        isAnalyzing = true
        analyses = []; summary = nil; dependencyEdges = []; leakIssues = []; archReport = nil
        functions = []; qualityReport = nil; gitHistoryReport = nil
        healthScore = nil; actionItems = []; healthTrend = nil; orphanedFiles = []

        let results = await analyzer.analyzeProject(at: url)
        analyses = results
        summary  = analyzer.generateSummary(from: results)

        let depAnalyzer = DependencyAnalyzer()
        let edges = await Task.detached(priority: .userInitiated) {
            depAnalyzer.analyze(files: results)
        }.value
        dependencyEdges = edges
        let depStats = DependencyStats.compute(analyses: results, edges: edges)
        let orphanedPaths = Set(depStats.orphanedFilePaths)
        orphanedFiles = results.filter { orphanedPaths.contains($0.filePath) }

        let leaks = await Task.detached(priority: .userInitiated) {
            MemoryLeakAnalyzer().analyze(files: results)
        }.value
        leakIssues = leaks

        let archRep = await Task.detached(priority: .userInitiated) {
            ArchitectureAnalyzer().analyze(files: results, edges: edges)
        }.value
        archReport = archRep

        let funcs = await Task.detached(priority: .userInitiated) {
            FunctionAnalyzer().analyze(files: results)
        }.value
        functions = funcs

        let quality = await Task.detached(priority: .userInitiated) {
            CodeQualityAnalyzer().analyze(files: results, functions: funcs)
        }.value
        qualityReport = quality

        let gitRep = await Task.detached(priority: .userInitiated) { [path = url.path] in
            GitHistoryAnalyzer().analyze(projectPath: path, files: results)
        }.value
        gitHistoryReport = gitRep

        // 건강 점수 & 액션 생성
        let calculator = HealthScoreCalculator()
        let health = calculator.calculate(
            analyses: results,
            edges: edges,
            leaks: leaks,
            qualityReport: quality
        )
        healthScore = health
        let projectSnapshots = snapshots.filter { $0.projectPath == url.path }
        healthTrend = projectSnapshots.first.map { health.overall - $0.healthScore }
        actionItems = calculator.generateActions(
            analyses: results,
            edges: edges,
            leaks: leaks,
            archReport: archRep,
            qualityReport: quality,
            functions: funcs
        )
        saveSnapshot(health: health, projectPath: url.path)

        isAnalyzing = false
    }

    // MARK: - 스냅샷

    func loadSnapshots() {
        guard let data    = UserDefaults.standard.data(forKey: "cca_snapshots"),
              let decoded = try? JSONDecoder().decode([ProjectSnapshot].self, from: data)
        else { return }
        snapshots = decoded
    }

    private func saveSnapshot(health: HealthScore, projectPath: String) {
        let snapshot = ProjectSnapshot(
            id:                   UUID(),
            date:                 Date(),
            projectPath:          projectPath,
            healthScore:          health.overall,
            grade:                health.grade.rawValue,
            complexityScore:      health.complexityComponent,
            dependencyScore:      health.dependencyComponent,
            memoryScore:          health.memoryComponent,
            qualityScore:         health.qualityComponent,
            totalFiles:           summary?.totalFiles      ?? 0,
            totalFunctions:       summary?.totalFunctions  ?? 0,
            averageComplexity:    summary?.averageComplexity ?? 0,
            memoryIssueCount:     leakIssues.filter { $0.severity == .high }.count,
            qualityOverallScore:  qualityReport?.overallScore ?? 0
        )
        var current = snapshots.filter { $0.projectPath == projectPath }
        current.insert(snapshot, at: 0)
        if current.count > 5 { current = Array(current.prefix(5)) }
        let others = snapshots.filter { $0.projectPath != projectPath }
        snapshots = current + others
        if let data = try? JSONEncoder().encode(snapshots) {
            UserDefaults.standard.set(data, forKey: "cca_snapshots")
        }
    }

    // MARK: - 내보내기

    func exportReport(format: ExportFormat) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = "code_analysis.\(format.fileExtension)"
        panel.message = "분석 결과를 저장할 위치를 선택하세요"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let content = self.generate(format: format)
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
                self.showAlert(title: "내보내기 완료",
                               message: "\(format.rawValue) 파일이 저장되었습니다.\n\(url.path)",
                               style: .informational)
            } catch {
                self.showAlert(title: "저장 실패",
                               message: error.localizedDescription,
                               style: .critical)
            }
        }
    }

    private func generate(format: ExportFormat) -> String {
        switch format {
        case .markdown: return generateMarkdown()
        case .json:     return generateJSON()
        case .csv:      return generateCSV()
        }
    }

    // MARK: - Markdown

    private func generateMarkdown() -> String {
        let date = DateFormatter.localizedString(from: Date(),
                                                 dateStyle: .long, timeStyle: .short)
        var md = """
        # 코드 복잡도 분석 리포트

        > 생성: \(date)
        > 프로젝트: \(selectedPath ?? "-")

        ---

        """

        // ── 요약 ──────────────────────────────────────────────────────────────
        if let s = summary {
            md += "## 📊 프로젝트 요약\n\n"
            md += "| 항목 | 값 |\n|------|-----|\n"
            md += "| 총 파일 | \(s.totalFiles)개 |\n"
            md += "| 총 라인 | \(s.totalLines.formatted())줄 |\n"
            md += "| 총 함수 | \(s.totalFunctions)개 |\n"
            md += "| 평균 복잡도 | \(String(format: "%.1f", s.averageComplexity)) |\n"
            if let mc = s.mostComplexFile {
                md += "| 가장 복잡한 파일 | \(mc.fileName) (\(String(format: "%.1f", mc.complexityScore))) |\n"
            }
            if let lf = s.largestFile {
                md += "| 가장 큰 파일 | \(lf.fileName) (\(lf.lineCount)줄) |\n"
            }
            md += "\n"
        }

        // ── 복잡도 등급 분포 ──────────────────────────────────────────────────
        md += "### 복잡도 등급 분포\n\n"
        md += "| 등급 | 파일 수 |\n|------|--------|\n"
        for level in ComplexityLevel.allCases {
            let cnt = analyses.filter { $0.complexityLevel == level }.count
            md += "| \(level.rawValue) | \(cnt)개 |\n"
        }
        md += "\n---\n\n"

        // ── 파일별 복잡도 ─────────────────────────────────────────────────────
        md += "## 📁 파일별 복잡도\n\n"
        md += "| # | 파일명 | 복잡도 | 등급 | 라인 | 함수 | 순환복잡도 | Class | Struct | Enum | Protocol |\n"
        md += "|---|--------|--------|------|------|------|-----------|-------|--------|------|----------|\n"
        let sorted = analyses.sorted { $0.complexityScore > $1.complexityScore }
        for (i, a) in sorted.enumerated() {
            md += "| \(i+1) | `\(a.fileName)` | \(String(format: "%.1f", a.complexityScore)) "
            md += "| \(a.complexityLevel.rawValue) | \(a.lineCount) | \(a.functionCount) "
            md += "| \(a.cyclomaticComplexity) | \(a.classCount) | \(a.structCount) "
            md += "| \(a.enumCount) | \(a.protocolCount) |\n"
        }
        md += "\n---\n\n"

        // ── 의존성 분석 ───────────────────────────────────────────────────────
        if !dependencyEdges.isEmpty {
            let stats = DependencyStats.compute(analyses: analyses, edges: dependencyEdges)
            md += "## 🔗 의존성 분석\n\n"
            md += "| 항목 | 값 |\n|------|-----|\n"
            md += "| 총 의존 관계 | \(stats.totalEdges)개 |\n"
            md += "| 순환 의존 파일 | \(stats.cyclicNodes.count)개 |\n"
            md += "| 독립 파일 | \(stats.isolatedFilePaths.count)개 |\n"
            if let top = stats.mostReferenced,
               let name = analyses.first(where: { $0.filePath == top.path })?.fileName {
                md += "| 가장 많이 참조됨 | \(name) (\(top.count)회) |\n"
            }
            md += "\n"

            if !stats.cyclicNodes.isEmpty {
                md += "### 순환 의존성 파일 목록\n\n"
                for fp in stats.cyclicNodes.sorted() {
                    let name = analyses.first(where: { $0.filePath == fp })?.fileName ?? fp
                    md += "- `\(name)`\n"
                }
                md += "\n"
            }

            md += "### 의존 관계 목록\n\n"
            md += "| From | To | 공유 타입 |\n|------|----|-----------|\n"
            for edge in dependencyEdges.sorted(by: { $0.fromFilePath < $1.fromFilePath }) {
                let from = analyses.first(where: { $0.filePath == edge.fromFilePath })?.fileName ?? edge.fromFilePath
                let to   = analyses.first(where: { $0.filePath == edge.toFilePath   })?.fileName ?? edge.toFilePath
                md += "| `\(from)` | `\(to)` | \(edge.sharedTypes.joined(separator: ", ")) |\n"
            }
            md += "\n---\n\n"
        }

        // ── 메모리 릭 이슈 ────────────────────────────────────────────────────
        md += "## 🚨 메모리 릭 이슈\n\n"
        if leakIssues.isEmpty {
            md += "> ✅ 잠재적인 메모리 릭 패턴이 발견되지 않았습니다.\n\n"
        } else {
            // 요약
            md += "| 심각도 | 개수 |\n|--------|------|\n"
            for sev in MemoryLeakIssue.Severity.allCases {
                let cnt = leakIssues.filter { $0.severity == sev }.count
                md += "| \(sev.rawValue) | \(cnt)개 |\n"
            }
            md += "\n"

            // 상세 목록
            md += "| 파일명 | 라인 | 이슈 유형 | 심각도 | 설명 |\n"
            md += "|--------|------|-----------|--------|------|\n"
            for issue in leakIssues.sorted(by: { $0.severity < $1.severity }) {
                let desc = issue.description
                    .replacingOccurrences(of: "\n", with: " ")
                    .replacingOccurrences(of: "|", with: "｜")
                md += "| `\(issue.fileName)` | \(issue.lineNumber) "
                md += "| \(issue.issueType.rawValue) | \(issue.severity.rawValue) | \(desc) |\n"
            }
            md += "\n"
        }
        md += "---\n\n"

        // ── 아키텍처 분석 ──────────────────────────────────────────────────────
        md += "## 🏛️ 아키텍처 분석\n\n"
        if let arch = archReport {
            md += "| 항목 | 값 |\n|------|-----|\n"
            md += "| 감지 패턴 | \(arch.pattern.rawValue) |\n"
            md += "| 패턴 신뢰도 | \(String(format: "%.0f%%", arch.patternConfidence * 100)) |\n"
            md += "| 종합 점수 | \(String(format: "%.1f / 100", arch.healthScore)) |\n"
            md += "| 레이어 분리도 | \(String(format: "%.1f", arch.separationScore)) |\n"
            md += "| 명명 준수도 | \(String(format: "%.1f", arch.namingScore)) |\n"
            md += "| 의존 방향 준수 | \(String(format: "%.1f", arch.dependencyScore)) |\n"
            md += "\n"

            // 레이어 분포
            md += "### 레이어 분포\n\n"
            md += "| 레이어 | 파일 수 |\n|--------|--------|\n"
            for layer in ArchLayer.allCases {
                let cnt = arch.layerInfos.filter { $0.layer == layer }.count
                if cnt > 0 { md += "| \(layer.rawValue) | \(cnt)개 |\n" }
            }
            md += "\n"

            // 파일별 레이어 분류
            md += "### 파일 레이어 분류\n\n"
            md += "| 파일명 | 레이어 | 분류 근거 |\n|--------|--------|----------|\n"
            for info in arch.layerInfos.sorted(by: { $0.layer.rawValue < $1.layer.rawValue }) {
                let reason = info.reasons.first?
                    .replacingOccurrences(of: "|", with: "｜") ?? "-"
                md += "| `\(info.file.fileName)` | \(info.layer.rawValue) | \(reason) |\n"
            }
            md += "\n"

            // 아키텍처 이슈
            md += "### 아키텍처 이슈\n\n"
            if arch.issues.isEmpty {
                md += "> ✅ 아키텍처 관점의 이슈가 발견되지 않았습니다.\n\n"
            } else {
                md += "| 파일명 | 이슈 유형 | 심각도 | 설명 |\n"
                md += "|--------|-----------|--------|------|\n"
                for issue in arch.issues {
                    let desc = issue.description
                        .replacingOccurrences(of: "\n", with: " ")
                        .replacingOccurrences(of: "|", with: "｜")
                    md += "| `\(issue.fileName)` | \(issue.type.rawValue) | \(issue.severity.rawValue) | \(desc) |\n"
                }
                md += "\n"
            }
        } else {
            md += "> 아키텍처 분석 데이터가 없습니다.\n\n"
        }

        return md
    }

    // MARK: - JSON

    private func generateJSON() -> String {
        let date = ISO8601DateFormatter().string(from: Date())

        // summary
        var summaryObj = "null"
        if let s = summary {
            summaryObj = """
            {
                "totalFiles": \(s.totalFiles),
                "totalLines": \(s.totalLines),
                "totalFunctions": \(s.totalFunctions),
                "averageComplexity": \(String(format: "%.2f", s.averageComplexity)),
                "mostComplexFile": \(s.mostComplexFile.map { "\"\($0.fileName)\"" } ?? "null"),
                "largestFile": \(s.largestFile.map { "\"\($0.fileName)\"" } ?? "null")
            }
            """
        }

        // files array
        let filesArr = analyses
            .sorted { $0.complexityScore > $1.complexityScore }
            .map { a -> String in
                """
                    {
                        "fileName": \(jsonStr(a.fileName)),
                        "filePath": \(jsonStr(a.filePath)),
                        "complexityScore": \(String(format: "%.2f", a.complexityScore)),
                        "complexityLevel": \(jsonStr(a.complexityLevel.rawValue)),
                        "lineCount": \(a.lineCount),
                        "functionCount": \(a.functionCount),
                        "cyclomaticComplexity": \(a.cyclomaticComplexity),
                        "classCount": \(a.classCount),
                        "structCount": \(a.structCount),
                        "enumCount": \(a.enumCount),
                        "protocolCount": \(a.protocolCount),
                        "propertyCount": \(a.propertyCount)
                    }
                """
            }
            .joined(separator: ",\n")

        // dependencies
        let stats = DependencyStats.compute(analyses: analyses, edges: dependencyEdges)
        let cyclicArr = stats.cyclicNodes.sorted().map { jsonStr($0) }.joined(separator: ", ")
        let edgesArr = dependencyEdges.map { e -> String in
            let types = e.sharedTypes.map { jsonStr($0) }.joined(separator: ", ")
            return """
                    {
                        "from": \(jsonStr(e.fromFilePath)),
                        "to": \(jsonStr(e.toFilePath)),
                        "sharedTypes": [\(types)]
                    }
                """
        }.joined(separator: ",\n")

        // memory leaks
        let leaksArr = leakIssues.map { issue -> String in
            """
                    {
                        "fileName": \(jsonStr(issue.fileName)),
                        "filePath": \(jsonStr(issue.filePath)),
                        "lineNumber": \(issue.lineNumber),
                        "lineContent": \(jsonStr(issue.lineContent)),
                        "issueType": \(jsonStr(issue.issueType.rawValue)),
                        "severity": \(jsonStr(issue.severity.rawValue)),
                        "description": \(jsonStr(issue.description)),
                        "suggestion": \(jsonStr(issue.suggestion))
                    }
                """
        }.joined(separator: ",\n")

        // architecture
        var archObj = "null"
        if let arch = archReport {
            let layerDist = ArchLayer.allCases.map { layer -> String in
                let cnt = arch.layerInfos.filter { $0.layer == layer }.count
                return "            \(jsonStr(layer.rawValue)): \(cnt)"
            }.joined(separator: ",\n")

            let layerInfosArr = arch.layerInfos.map { info -> String in
                """
                            {
                                "fileName": \(jsonStr(info.file.fileName)),
                                "filePath": \(jsonStr(info.file.filePath)),
                                "layer": \(jsonStr(info.layer.rawValue)),
                                "reasons": [\(info.reasons.map { jsonStr($0) }.joined(separator: ", "))]
                            }
                    """
            }.joined(separator: ",\n")

            let archIssuesArr = arch.issues.map { issue -> String in
                """
                            {
                                "fileName": \(jsonStr(issue.fileName)),
                                "filePath": \(jsonStr(issue.filePath)),
                                "issueType": \(jsonStr(issue.type.rawValue)),
                                "severity": \(jsonStr(issue.severity.rawValue)),
                                "description": \(jsonStr(issue.description)),
                                "suggestion": \(jsonStr(issue.suggestion))
                            }
                    """
            }.joined(separator: ",\n")

            archObj = """
            {
                    "pattern": \(jsonStr(arch.pattern.rawValue)),
                    "patternConfidence": \(String(format: "%.2f", arch.patternConfidence)),
                    "healthScore": \(String(format: "%.1f", arch.healthScore)),
                    "separationScore": \(String(format: "%.1f", arch.separationScore)),
                    "namingScore": \(String(format: "%.1f", arch.namingScore)),
                    "dependencyScore": \(String(format: "%.1f", arch.dependencyScore)),
                    "layerDistribution": {
            \(layerDist)
                    },
                    "layerInfos": [
            \(layerInfosArr)
                    ],
                    "issues": [
            \(archIssuesArr)
                    ]
                }
            """
        }

        return """
        {
            "metadata": {
                "generatedAt": "\(date)",
                "projectPath": \(jsonStr(selectedPath ?? ""))
            },
            "summary": \(summaryObj),
            "files": [
        \(filesArr)
            ],
            "dependencies": {
                "totalEdges": \(stats.totalEdges),
                "cyclicFileCount": \(stats.cyclicNodes.count),
                "isolatedFileCount": \(stats.isolatedFilePaths.count),
                "cyclicFiles": [\(cyclicArr)],
                "edges": [
        \(edgesArr)
                ]
            },
            "memoryLeaks": {
                "total": \(leakIssues.count),
                "high": \(leakIssues.filter { $0.severity == .high }.count),
                "medium": \(leakIssues.filter { $0.severity == .medium }.count),
                "low": \(leakIssues.filter { $0.severity == .low }.count),
                "issues": [
        \(leaksArr)
                ]
            },
            "architecture": \(archObj)
        }
        """
    }

    private func jsonStr(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    // MARK: - CSV

    private func generateCSV() -> String {
        var csv = ""

        // ── 섹션 1: 파일별 복잡도 ─────────────────────────────────────────────
        csv += "## 파일별 복잡도\n"
        csv += "파일명,파일경로,복잡도점수,복잡도등급,라인수,함수수,순환복잡도,클래스,스트럭트,열거형,프로토콜,프로퍼티\n"
        for a in analyses.sorted(by: { $0.complexityScore > $1.complexityScore }) {
            csv += "\(csvEsc(a.fileName)),\(csvEsc(a.filePath)),"
            csv += "\(String(format: "%.2f", a.complexityScore)),\(csvEsc(a.complexityLevel.rawValue)),"
            csv += "\(a.lineCount),\(a.functionCount),\(a.cyclomaticComplexity),"
            csv += "\(a.classCount),\(a.structCount),\(a.enumCount),\(a.protocolCount),\(a.propertyCount)\n"
        }

        csv += "\n## 의존 관계\n"
        csv += "From파일,To파일,공유타입수,공유타입목록\n"
        for edge in dependencyEdges.sorted(by: { $0.fromFilePath < $1.fromFilePath }) {
            let from = analyses.first(where: { $0.filePath == edge.fromFilePath })?.fileName ?? edge.fromFilePath
            let to   = analyses.first(where: { $0.filePath == edge.toFilePath   })?.fileName ?? edge.toFilePath
            csv += "\(csvEsc(from)),\(csvEsc(to)),\(edge.sharedTypes.count),\(csvEsc(edge.sharedTypes.joined(separator: " | ")))\n"
        }

        csv += "\n## 메모리 릭 이슈\n"
        csv += "파일명,파일경로,라인번호,이슈유형,심각도,설명,수정제안\n"
        for issue in leakIssues.sorted(by: { $0.severity < $1.severity }) {
            csv += "\(csvEsc(issue.fileName)),\(csvEsc(issue.filePath)),\(issue.lineNumber),"
            csv += "\(csvEsc(issue.issueType.rawValue)),\(csvEsc(issue.severity.rawValue)),"
            csv += "\(csvEsc(issue.description)),\(csvEsc(issue.suggestion))\n"
        }

        // ── 섹션 4: 아키텍처 분석 ─────────────────────────────────────────────
        if let arch = archReport {
            csv += "\n## 아키텍처 분석\n"
            csv += "감지패턴,패턴신뢰도,종합점수,레이어분리도,명명준수도,의존방향준수\n"
            csv += "\(csvEsc(arch.pattern.rawValue)),"
            csv += "\(String(format: "%.0f%%", arch.patternConfidence * 100)),"
            csv += "\(String(format: "%.1f", arch.healthScore)),"
            csv += "\(String(format: "%.1f", arch.separationScore)),"
            csv += "\(String(format: "%.1f", arch.namingScore)),"
            csv += "\(String(format: "%.1f", arch.dependencyScore))\n"

            csv += "\n## 레이어 분포\n"
            csv += "레이어,파일수\n"
            for layer in ArchLayer.allCases {
                let cnt = arch.layerInfos.filter { $0.layer == layer }.count
                if cnt > 0 { csv += "\(csvEsc(layer.rawValue)),\(cnt)\n" }
            }

            csv += "\n## 파일 레이어 분류\n"
            csv += "파일명,파일경로,레이어,분류근거\n"
            for info in arch.layerInfos.sorted(by: { $0.layer.rawValue < $1.layer.rawValue }) {
                let reason = info.reasons.first ?? "-"
                csv += "\(csvEsc(info.file.fileName)),\(csvEsc(info.file.filePath)),"
                csv += "\(csvEsc(info.layer.rawValue)),\(csvEsc(reason))\n"
            }

            csv += "\n## 아키텍처 이슈\n"
            csv += "파일명,파일경로,이슈유형,심각도,설명,수정제안\n"
            for issue in arch.issues {
                csv += "\(csvEsc(issue.fileName)),\(csvEsc(issue.filePath)),"
                csv += "\(csvEsc(issue.type.rawValue)),\(csvEsc(issue.severity.rawValue)),"
                csv += "\(csvEsc(issue.description)),\(csvEsc(issue.suggestion))\n"
            }
        }

        return csv
    }

    private func csvEsc(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        let needsQuotes = escaped.contains(",") || escaped.contains("\"")
                       || escaped.contains("\n") || escaped.contains("\r")
        return needsQuotes ? "\"\(escaped)\"" : escaped
    }

    // MARK: - 알림

    private func showAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText     = title
        alert.informativeText = message
        alert.alertStyle      = style
        alert.addButton(withTitle: "확인")
        alert.runModal()
    }
}
