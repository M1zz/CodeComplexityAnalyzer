import SwiftUI
import AppKit

// MARK: - PromptMode

enum PromptMode: String, CaseIterable, Identifiable {
    case diagnosis    = "진단"
    case refactoring  = "리팩토링"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .diagnosis:   return "stethoscope"
        case .refactoring: return "wrench.and.screwdriver"
        }
    }

    var description: String {
        switch self {
        case .diagnosis:
            return "정적 분석 데이터를 Claude에게 넘겨 오탐 검증과 놓친 패턴을 찾아달라고 합니다."
        case .refactoring:
            return "앱이 발견한 의존성·메모리·레이어 문제를 포함해 Claude Code가 놓칠 수 있는 맥락까지 전달합니다."
        }
    }
}

// MARK: - AIReportView

struct AIReportView: View {
    let analyses:     [FileAnalysis]
    let summary:      ProjectSummary?
    let healthScore:  HealthScore?
    let actionItems:  [ActionItem]
    let selectedPath: String?
    let archReport:   ArchReport?
    let leakIssues:   [MemoryLeakIssue]
    let dependencyEdges: [DependencyEdge]

    @AppStorage("cca_ai_report_text") private var savedReport = ""
    @State private var promptCopied = false
    @State private var promptMode: PromptMode = .diagnosis

    var body: some View {
        HSplitView {
            leftPanel.frame(minWidth: 420)
            rightPanel.frame(minWidth: 320, maxWidth: 440)
        }
    }

    // MARK: - Left: 붙여넣기 영역

    private var leftPanel: some View {
        VStack(spacing: 0) {
            // 헤더
            HStack(spacing: 10) {
                Image(systemName: "brain")
                    .font(.title3)
                    .foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AI 진단 리포트")
                        .font(.headline)
                    Text("Claude가 분석한 결과를 아래에 붙여넣으세요")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !savedReport.isEmpty {
                    Button(role: .destructive) { savedReport = "" } label: {
                        Label("지우기", systemImage: "trash")
                            .font(.body)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color(.windowBackgroundColor))

            Divider()

            // 텍스트 에디터
            if savedReport.isEmpty {
                emptyPasteView
            } else {
                ScrollView {
                    Text(savedReport)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(.textBackgroundColor))
            }
        }
    }

    private var emptyPasteView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundColor(.secondary.opacity(0.4))
            Text("Claude 분석 결과를 붙여넣으세요")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            PasteButton(payloadType: String.self) { strings in
                savedReport = strings.joined(separator: "\n")
            }
            .controlSize(.large)

            Text("또는 아래 영역을 클릭해서 직접 입력")
                .font(.body)
                .foregroundColor(.secondary)

            TextEditor(text: $savedReport)
                .font(.system(.body, design: .monospaced))
                .frame(height: 120)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2)))
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.controlBackgroundColor))
    }

    // MARK: - Right: 프롬프트 생성 패널

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 모드 선택
                modeSelectorCard

                // 프롬프트 복사 버튼
                promptCopyCard

                // 현재 분석 요약
                if let s = summary {
                    currentSummaryCard(s)
                }

                // 사용 방법 안내
                howToCard
            }
            .padding()
        }
        .background(Color(.controlBackgroundColor))
    }

    private var modeSelectorCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("프롬프트 모드", systemImage: "slider.horizontal.3")
                .font(.headline)

            Picker("", selection: $promptMode) {
                ForEach(PromptMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(promptMode.description)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
    }

    private var promptCopyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(makePrompt(), forType: .string)
                withAnimation { promptCopied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { promptCopied = false }
                }
            } label: {
                Label(
                    promptCopied ? "복사됨!" : "프롬프트 복사",
                    systemImage: promptCopied ? "checkmark.circle.fill" : "doc.on.clipboard"
                )
                .font(.body).fontWeight(.semibold)
                .foregroundColor(promptCopied ? .green : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(promptCopied ? .green : .purple)

            Text("복사 후 터미널에서 \(promptMode == .diagnosis ? "claude" : "claude") 명령에 붙여넣으세요.")
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
    }

    private func currentSummaryCard(_ summary: ProjectSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("현재 분석 요약", systemImage: "chart.bar")
                .font(.headline)

            statRow("파일 수", "\(summary.totalFiles)개")
            statRow("총 라인", "\(summary.totalLines)줄")
            statRow("함수 수", "\(summary.totalFunctions)개")
            statRow("평균 복잡도", String(format: "%.1f", summary.averageComplexity))
            if let h = healthScore {
                statRow("건강 점수", String(format: "%.0f점 (%@)", h.overall, h.grade.rawValue))
            }
            statRow("할 일 항목", "\(actionItems.count)개")
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.body).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.body).fontWeight(.medium)
        }
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("사용 방법", systemImage: "questionmark.circle")
                .font(.headline)

            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.body).fontWeight(.bold)
                        .foregroundColor(.purple)
                        .frame(width: 20)
                    Text(step)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
    }

    private let steps = [
        "모드를 선택합니다. 진단은 처음 검토 시, 리팩토링은 실제 코드 수정 의뢰 시 사용합니다.",
        "\"프롬프트 복사\" 버튼을 누릅니다.",
        "터미널에서 claude 명령을 실행하고 프롬프트를 붙여넣습니다.",
        "Claude의 분석 결과 전체를 복사합니다.",
        "왼쪽 영역에 붙여넣으면 자동 저장됩니다.",
    ]

    // MARK: - 프롬프트 생성

    private func makePrompt() -> String {
        switch promptMode {
        case .diagnosis:   return makeDiagnosisPrompt()
        case .refactoring: return makeRefactoringPrompt()
        }
    }

    private func makeDiagnosisPrompt() -> String {
        let path = selectedPath ?? "(경로 미선택)"

        var topFiles = ""
        if !analyses.isEmpty {
            topFiles = analyses.prefix(10)
                .map { "  - \($0.fileName): \($0.lineCount)줄, 함수 \($0.functionCount)개, CC \($0.cyclomaticComplexity)" }
                .joined(separator: "\n")
        }

        var actionSummary = ""
        if !actionItems.isEmpty {
            actionSummary = actionItems.prefix(10).enumerated()
                .map { i, a in
                    let sev = a.severity == .critical ? "🔴" : a.severity == .warning ? "🟠" : "🔵"
                    return "  \(i+1). [\(sev) \(a.category.rawValue)] \(a.title) — \(a.fileName)"
                }
                .joined(separator: "\n")
        }

        let healthLine = healthSummaryLine()

        return """
        아래는 Swift 프로젝트를 정적 분석한 결과입니다.
        정적 분석 도구의 한계(주석 포함 카운트, 이스케이핑 판단 오류 등)를 감안해서,
        실제 코드를 직접 확인하고 더 정확한 진단을 내려주세요.

        ## 프로젝트 경로
        \(path)

        ## 정적 분석 요약
        - 파일 수: \(summary?.totalFiles ?? 0)개
        - 총 라인: \(summary?.totalLines ?? 0)줄
        - 총 함수: \(summary?.totalFunctions ?? 0)개
        - 평균 복잡도: \(String(format: "%.1f", summary?.averageComplexity ?? 0))
        - \(healthLine)

        ## 복잡도 상위 파일 (최대 10개)
        \(topFiles.isEmpty ? "  없음" : topFiles)

        ## 정적 분석이 지적한 주요 할 일 (최대 10개)
        \(actionSummary.isEmpty ? "  없음" : actionSummary)

        ## 요청사항
        1. 위 데이터를 바탕으로 실제 코드를 열어서 정적 분석 오탐 여부를 판단해주세요.
        2. 정적 도구가 놓쳤지만 실제로 문제가 되는 패턴이 있으면 알려주세요.
        3. 가장 시급하게 살펴봐야 할 파일과 이유를 우선순위 순서로 정리해주세요.
        4. 각 문제에 대해 어떤 방향으로 개선하면 좋을지 간단히 제안해주세요. 수정 코드는 필요 없고, 방향만 알려주세요.
        """
    }

    private func makeRefactoringPrompt() -> String {
        let path = selectedPath ?? "(경로 미선택)"

        // 순환 의존성
        let cyclicNodes = DependencyAnalyzer.findCyclicNodes(from: dependencyEdges)
        let cyclicList = analyses
            .filter { cyclicNodes.contains($0.filePath) }
            .prefix(5)
            .map { "  - \($0.fileName)" }
            .joined(separator: "\n")

        // 메모리 이슈 (unique file+type, high only)
        struct MemKey: Hashable { let path: String; let type: MemoryLeakIssue.IssueType }
        var seen = Set<MemKey>()
        let highLeaks = leakIssues
            .filter { $0.severity == .high }
            .filter { seen.insert(MemKey(path: $0.filePath, type: $0.issueType)).inserted }
            .prefix(5)
        let memoryList = highLeaks
            .map { "  - \($0.fileName) (\($0.issueType.rawValue)): \($0.suggestion)" }
            .joined(separator: "\n")

        // 아키텍처 이슈
        let archIssues = archReport?.issues.filter { $0.severity == .high }.prefix(5) ?? []
        let archList = archIssues
            .map { "  - \($0.fileName) [\($0.type.rawValue)]: \($0.description)" }
            .joined(separator: "\n")

        // 레이어 분포
        var layerSummary = ""
        if let arch = archReport {
            let groups = Dictionary(grouping: arch.layerInfos, by: { $0.layer.rawValue })
            layerSummary = groups.map { "\($0.key): \($0.value.count)개" }
                .sorted().joined(separator: ", ")
        }

        let healthLine = healthSummaryLine()

        return """
        아래는 Swift 프로젝트 리팩토링 의뢰입니다.
        프로젝트 경로를 직접 열어 파일을 읽고 코드를 수정해주세요.

        ## 프로젝트 경로
        \(path)

        ## 건강 점수 현황
        \(healthLine)

        ## 🔴 앱 분석기가 발견한 문제 (Claude Code가 기본적으로 놓칠 수 있는 항목)

        ### 1. 순환 의존성 (의존성 가중치 15%)
        \(cyclicList.isEmpty ? "  없음" : cyclicList)
        → 해결 방법: 프로토콜로 추상화하거나 의존 방향을 단방향으로 정리해주세요.

        ### 2. 메모리 누수 패턴 (메모리 가중치 20%)
        \(memoryList.isEmpty ? "  없음" : memoryList)
        → 해결 방법: [weak self], weak delegate 선언, Timer 무효화, 알림 옵저버 제거로 수정해주세요.

        ### 3. 아키텍처 레이어 위반 (아키텍처 가중치 20%)
        \(archList.isEmpty ? "  없음" : archList)
        레이어 분포: \(layerSummary.isEmpty ? "미분석" : layerSummary)
        → 해결 방법: View가 Data를 직접 다루거나 반대 방향 의존이 있으면 레이어를 분리해주세요.

        ## 🟠 정적 분석 기반 우선순위 할 일
        \(actionItems.prefix(10).enumerated().map { i, a in
            let sev = a.severity == .critical ? "🔴" : a.severity == .warning ? "🟠" : "🔵"
            return "  \(i+1). [\(sev) \(a.category.rawValue)] \(a.title) — \(a.fileName) (예상 개선: +\(String(format: "%.1f", a.impactScore))점)"
        }.joined(separator: "\n"))

        ## 요청사항
        1. 위 항목 중 실제로 문제가 되는 것과 오탐인 것을 구분해주세요.
        2. 각 문제를 어떤 방향으로 개선하면 좋을지 간단히 제안해주세요. 수정 코드는 필요 없고, 방향만 알려주세요.
        3. 우선순위가 높은 항목 3가지만 꼽아주세요. 이유도 한 줄씩 적어주세요.
        4. 개선 후 건강 점수가 어느 정도 오를지 대략적으로 추정해주세요.
        """
    }

    private func healthSummaryLine() -> String {
        guard let h = healthScore else { return "건강 점수: 미분석" }
        return "건강 점수: \(String(format: "%.0f", h.overall))점 (\(h.grade.rawValue)) — 복잡도 \(String(format: "%.0f", h.complexityComponent))점 / 의존성 \(String(format: "%.0f", h.dependencyComponent))점 / 메모리 \(String(format: "%.0f", h.memoryComponent))점 / 품질 \(String(format: "%.0f", h.qualityComponent))점 / 아키텍처 \(String(format: "%.0f", h.architectureComponent))점"
    }
}
