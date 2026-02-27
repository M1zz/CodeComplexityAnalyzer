import SwiftUI
import Charts
import AppKit

// MARK: - Main View

struct MemoryLeakView: View {
    let issues: [MemoryLeakIssue]

    @State private var selectedIssueType: MemoryLeakIssue.IssueType? = nil
    @State private var selectedSeverity:  MemoryLeakIssue.Severity?   = nil
    @State private var searchText = ""

    private var filtered: [MemoryLeakIssue] {
        issues.filter { issue in
            (selectedIssueType == nil || issue.issueType == selectedIssueType) &&
            (selectedSeverity   == nil || issue.severity  == selectedSeverity)  &&
            (searchText.isEmpty || issue.fileName.localizedCaseInsensitiveContains(searchText))
        }
        .sorted { $0.severity < $1.severity }
    }

    var body: some View {
        if issues.isEmpty {
            emptyView
        } else {
            HSplitView {
                // 왼쪽: 이슈 목록
                listPanel
                    .frame(minWidth: 420)

                // 오른쪽: 차트 대시보드
                dashboardPanel
                    .frame(minWidth: 300, maxWidth: 420)
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            Text("메모리 릭 위험 없음")
                .font(.title2).fontWeight(.semibold)
            Text("정적 분석 결과 잠재적인 메모리 릭 패턴이 발견되지 않았습니다.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List Panel

    private var listPanel: some View {
        VStack(spacing: 0) {
            // 필터 바
            filterBar
            Divider()
            // 이슈 리스트
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered) { issue in
                        IssueRow(issue: issue)
                    }
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("파일 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)

            HStack(spacing: 8) {
                // 이슈 타입 필터
                Menu {
                    Button("전체") { selectedIssueType = nil }
                    Divider()
                    ForEach(MemoryLeakIssue.IssueType.allCases, id: \.self) { t in
                        Button(t.rawValue) { selectedIssueType = t }
                    }
                } label: {
                    Label(
                        selectedIssueType?.rawValue ?? "이슈 타입",
                        systemImage: selectedIssueType?.icon ?? "line.3.horizontal.decrease.circle"
                    )
                    .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // 심각도 필터
                Menu {
                    Button("전체") { selectedSeverity = nil }
                    Divider()
                    ForEach(MemoryLeakIssue.Severity.allCases, id: \.self) { s in
                        Button(s.rawValue) { selectedSeverity = s }
                    }
                } label: {
                    Label(
                        selectedSeverity?.rawValue ?? "심각도",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Spacer()

                Text("\(filtered.count)개 이슈")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(Color(.windowBackgroundColor))
    }

    // MARK: - Dashboard Panel

    private var dashboardPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                severityCards
                issueTypeChart
                topFilesChart
            }
            .padding()
        }
        .background(Color(.controlBackgroundColor))
    }

    // 심각도 요약 카드
    private var severityCards: some View {
        HStack(spacing: 10) {
            ForEach(MemoryLeakIssue.Severity.allCases, id: \.self) { sev in
                let cnt = issues.filter { $0.severity == sev }.count
                VStack(spacing: 4) {
                    Text("\(cnt)")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(sev.color)
                    Text(sev.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(sev.color.opacity(0.1))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(sev.color.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }

    // 이슈 타입 분포 차트
    private var issueTypeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("이슈 유형별 분포")
                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)

            let data: [(type: String, count: Int)] = MemoryLeakIssue.IssueType.allCases.compactMap { t in
                let cnt = issues.filter { $0.issueType == t }.count
                return cnt > 0 ? (t.rawValue, cnt) : nil
            }

            Chart(data, id: \.type) { item in
                BarMark(
                    x: .value("개수", item.count),
                    y: .value("타입", item.type)
                )
                .foregroundStyle(Color.blue.gradient)
                .annotation(position: .trailing) {
                    Text("\(item.count)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(data.count * 38 + 10))
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
    }

    // 파일별 이슈 수 Top 5
    private var topFilesChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("파일별 이슈 수 (Top 5)")
                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)

            let fileCounts = Dictionary(grouping: issues, by: \.fileName)
                .map { (name: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }
                .prefix(5)

            Chart(fileCounts, id: \.name) { item in
                BarMark(
                    x: .value("개수", item.count),
                    y: .value("파일", item.name)
                )
                .foregroundStyle(Color.orange.gradient)
                .annotation(position: .trailing) {
                    Text("\(item.count)")
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(min(fileCounts.count, 5) * 38 + 10))
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(10)
    }
}

// MARK: - Issue Row

struct IssueRow: View {
    let issue: MemoryLeakIssue
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더 행
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    // 심각도 색상 바
                    Rectangle()
                        .fill(issue.severity.color)
                        .frame(width: 4)

                    // 이슈 아이콘
                    Image(systemName: issue.issueType.icon)
                        .font(.body)
                        .foregroundColor(issue.severity.color)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(issue.fileName)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                            Text(":\(issue.lineNumber)")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Text(issue.issueType.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // 심각도 뱃지
                    Text(issue.severity.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(issue.severity.color.opacity(0.15))
                        .foregroundColor(issue.severity.color)
                        .cornerRadius(4)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                .padding(.trailing, 12)
                .background(Color(.controlBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 확장 상세
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()

                    // 코드 스니펫
                    Text(issue.lineContent)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(6)

                    // 설명
                    Label(issue.description, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // 제안
                    VStack(alignment: .leading, spacing: 4) {
                        Label("수정 제안", systemImage: "lightbulb")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.yellow)

                        Text(issue.suggestion)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.yellow.opacity(0.08))
                            .cornerRadius(6)
                    }

                    // 파일 경로
                    Text(issue.filePath)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // 프롬프트 복사 버튼
                    CopyPromptButton(issue: issue)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .background(Color(.textBackgroundColor))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - 프롬프트 복사 버튼

struct CopyPromptButton: View {
    let issue: MemoryLeakIssue
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(makePrompt(), forType: .string)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { copied = false }
            }
        } label: {
            Label(
                copied ? "복사됨!" : "AI 수정 프롬프트 복사",
                systemImage: copied ? "checkmark.circle.fill" : "doc.on.clipboard"
            )
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(copied ? .green : .accentColor)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func makePrompt() -> String {
        """
        다음 Swift 파일에서 메모리 릭 문제를 수정해줘.

        파일: \(issue.filePath)
        라인: \(issue.lineNumber)
        이슈 유형: \(issue.issueType.rawValue)

        문제가 되는 코드:
        ```swift
        \(issue.lineContent)
        ```

        문제 설명:
        \(issue.description)

        수정 방법:
        \(issue.suggestion)
        """
    }
}

// MARK: - Severity color helper

extension MemoryLeakIssue.Severity {
    var color: Color {
        switch self {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        }
    }
}
