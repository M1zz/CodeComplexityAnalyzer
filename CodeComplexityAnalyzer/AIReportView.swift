import SwiftUI
import AppKit

// MARK: - AIReportView

struct AIReportView: View {
    let analyses:     [FileAnalysis]
    let summary:      ProjectSummary?
    let healthScore:  HealthScore?
    let actionItems:  [ActionItem]
    let selectedPath: String?

    @AppStorage("cca_ai_report_text") private var savedReport = ""
    @State private var promptCopied = false

    var body: some View {
        HSplitView {
            leftPanel.frame(minWidth: 420)
            rightPanel.frame(minWidth: 300, maxWidth: 420)
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
                // 프롬프트 복사 버튼
                VStack(alignment: .leading, spacing: 8) {
                    Label("분석 프롬프트", systemImage: "text.bubble")
                        .font(.headline)

                    Text("아래 버튼을 눌러 프롬프트를 복사한 뒤\nClaude Code CLI(claude 명령)에 붙여넣으세요.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

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
                }
                .padding()
                .background(Color(.windowBackgroundColor))
                .cornerRadius(10)

                // 현재 분석 요약
                if let summary {
                    currentSummaryCard(summary: summary)
                }

                // 사용 방법 안내
                howToCard
            }
            .padding()
        }
        .background(Color(.controlBackgroundColor))
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
        "\"프롬프트 복사\" 버튼을 누릅니다.",
        "터미널에서 claude 명령을 실행하고 프롬프트를 붙여넣습니다.",
        "Claude의 분석 결과 전체를 복사합니다.",
        "왼쪽 영역에 붙여넣으면 자동 저장됩니다.",
    ]

    // MARK: - 프롬프트 생성

    private func makePrompt() -> String {
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

        let healthLine: String
        if let h = healthScore {
            healthLine = "건강 점수: \(String(format: "%.0f", h.overall))점 (\(h.grade.rawValue)) — 복잡도 \(String(format: "%.0f", h.complexityComponent))점 / 의존성 \(String(format: "%.0f", h.dependencyComponent))점 / 메모리 \(String(format: "%.0f", h.memoryComponent))점 / 품질 \(String(format: "%.0f", h.qualityComponent))점"
        } else {
            healthLine = "건강 점수: 미분석"
        }

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
        3. 가장 시급하게 고쳐야 할 파일과 이유를 우선순위 순서로 정리해주세요.
        4. 각 문제에 대해 구체적인 수정 코드도 함께 제시해주세요.
        """
    }
}
