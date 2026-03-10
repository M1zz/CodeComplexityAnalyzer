import SwiftUI
import Charts

// MARK: - Main View

struct ArchitectureView: View {
    let report: ArchReport
    let analyses: [FileAnalysis]
    let healthScore: HealthScore?

    private var potentialImprovement: Double {
        Double(report.issues.filter { $0.severity == .high }.prefix(3).count) * 2.0
        + Double(report.issues.filter { $0.severity == .medium }.prefix(5).count) * 0.8
    }

    @State private var selectedLayer:   ArchLayer?    = nil
    @State private var selectedIssueType: ArchIssue.IssueType? = nil
    @State private var issueSearch = ""

    private var filteredIssues: [ArchIssue] {
        report.issues.filter { issue in
            (selectedIssueType == nil || issue.type == selectedIssueType) &&
            (issueSearch.isEmpty || issue.fileName.localizedCaseInsensitiveContains(issueSearch))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            patternBanner
            Divider()
            HSplitView {
                leftPanel
                    .frame(minWidth: 360, maxWidth: 480)
                rightPanel
                    .frame(minWidth: 360)
            }
        }
    }

    // MARK: - Pattern Banner

    private var patternBanner: some View {
        HStack(spacing: 24) {
            // 패턴 아이콘 + 이름
            HStack(spacing: 10) {
                Image(systemName: report.pattern.icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(report.pattern.rawValue)
                        .font(.title3).fontWeight(.bold)
                    Text(report.pattern.description)
                        .font(.body).foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: 380, alignment: .leading)

            Spacer()

            // 신뢰도
            VStack(spacing: 4) {
                Text("패턴 신뢰도")
                    .font(.body).foregroundColor(.secondary)
                ConfidenceMeter(value: report.patternConfidence)
                    .frame(width: 120, height: 8)
                Text(String(format: "%.0f%%", report.patternConfidence * 100))
                    .font(.body).fontWeight(.semibold)
            }

            Divider().frame(height: 40)

            // 건강 점수
            healthGauge("분리도",    score: report.separationScore,  color: .blue)
            healthGauge("명명 준수", score: report.namingScore,       color: .green)
            healthGauge("의존 방향", score: report.dependencyScore,   color: .orange)

            Divider().frame(height: 40)

            // 종합 건강 점수
            VStack(spacing: 2) {
                Text("종합 점수")
                    .font(.body).foregroundColor(.secondary)
                Text(String(format: "%.0f", report.healthScore))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor(report.healthScore))
                Text("/ 100")
                    .font(.body).foregroundColor(.secondary)
            }

            Divider().frame(height: 40)

            // 건강점수 기여 & 예상 개선
            VStack(spacing: 2) {
                Text("건강점수 기여").font(.body).foregroundColor(.secondary)
                Text("20%").font(.title3).fontWeight(.bold).foregroundColor(.purple)
            }
            VStack(spacing: 2) {
                Text("이슈 해결 시").font(.body).foregroundColor(.secondary)
                Text(String(format: "+%.1f점", potentialImprovement))
                    .font(.title3).fontWeight(.bold).foregroundColor(.green)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
    }

    private func healthGauge(_ label: String, score: Double, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.body).foregroundColor(.secondary)
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: score / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.0f", score))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .frame(width: 44, height: 44)
        }
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 80 { return .green }
        if score >= 60 { return .orange }
        return .red
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                layerDistributionSection
                Divider()
                fileByLayerSection
            }
            .padding()
        }
        .background(Color(.windowBackgroundColor))
    }

    // 레이어 분포 차트
    private var layerDistributionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("레이어 분포")
                .font(.headline)

            let data = ArchLayer.allCases.compactMap { layer -> (layer: String, count: Int, icon: String)? in
                let cnt = report.layerInfos.filter { $0.layer == layer }.count
                return cnt > 0 ? (layer.rawValue, cnt, layer.icon) : nil
            }

            Chart(data, id: \.layer) { item in
                BarMark(
                    x: .value("파일 수", item.count),
                    y: .value("레이어",  item.layer)
                )
                .foregroundStyle(barColor(for: item.layer).gradient)
                .annotation(position: .trailing) {
                    Text("\(item.count)")
                        .font(.body).foregroundColor(.secondary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(data.count * 36 + 8))
        }
    }

    // 레이어별 파일 목록
    private var fileByLayerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("파일 분류")
                    .font(.headline)
                Spacer()
                if selectedLayer != nil {
                    Button("전체 보기") { selectedLayer = nil }
                        .font(.body).buttonStyle(.plain).foregroundColor(.accentColor)
                }
            }

            ForEach(ArchLayer.allCases, id: \.self) { layer in
                let layerFiles = report.layerInfos.filter { $0.layer == layer }
                if !layerFiles.isEmpty {
                    LayerGroupView(
                        layer: layer,
                        files: layerFiles,
                        isSelected: selectedLayer == layer,
                        onTap: {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedLayer = (selectedLayer == layer ? nil : layer)
                            }
                        }
                    )
                }
            }
        }
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(spacing: 0) {
            issueFilterBar
            Divider()
            if filteredIssues.isEmpty {
                emptyIssuesView
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(filteredIssues) { issue in
                            ArchIssueRow(issue: issue)
                        }
                    }
                }
            }
        }
    }

    private var issueFilterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("파일 검색...", text: $issueSearch)
                    .textFieldStyle(.plain)
                if !issueSearch.isEmpty {
                    Button { issueSearch = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)

            HStack {
                // 이슈 타입 필터
                Menu {
                    Button("전체") { selectedIssueType = nil }
                    Divider()
                    ForEach([ArchIssue.IssueType.massiveViewController,
                             .godObject, .layerViolation,
                             .singletonAbuse, .namingMismatch, .missingProtocol], id: \.self) { t in
                        Button(t.rawValue) { selectedIssueType = t }
                    }
                } label: {
                    Label(selectedIssueType?.rawValue ?? "이슈 유형",
                          systemImage: "line.3.horizontal.decrease.circle")
                        .font(.body)
                }
                .menuStyle(.borderlessButton).fixedSize()

                Spacer()

                // 심각도 요약 뱃지
                severitySummary

                BulkArchPromptButton(issues: filteredIssues)
            }
        }
        .padding(10)
        .background(Color(.windowBackgroundColor))
    }

    private var severitySummary: some View {
        HStack(spacing: 8) {
            severityBadge(
                count: report.issues.filter { $0.severity == .high }.count,
                color: .red, label: "높음"
            )
            severityBadge(
                count: report.issues.filter { $0.severity == .medium }.count,
                color: .orange, label: "중간"
            )
            severityBadge(
                count: report.issues.filter { $0.severity == .low }.count,
                color: .yellow, label: "낮음"
            )
        }
    }

    private func severityBadge(count: Int, color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text("\(count)")
                .font(.body).fontWeight(.semibold)
        }
    }

    private var emptyIssuesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48)).foregroundColor(.green)
            Text("감지된 이슈 없음")
                .font(.title3).fontWeight(.semibold)
            Text("아키텍처 관점에서 문제가 발견되지 않았습니다.")
                .font(.body).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func barColor(for layerName: String) -> Color {
        switch layerName {
        case ArchLayer.view.rawValue:        return .blue
        case ArchLayer.viewModel.rawValue:   return Color(red: 0.4, green: 0.6, blue: 1.0)
        case ArchLayer.model.rawValue:       return .green
        case ArchLayer.useCase.rawValue:     return .orange
        case ArchLayer.repository.rawValue:  return Color(red: 0.8, green: 0.4, blue: 0.0)
        case ArchLayer.service.rawValue:     return .purple
        case ArchLayer.coordinator.rawValue: return Color(red: 0.0, green: 0.7, blue: 0.7)
        default:                             return .secondary
        }
    }
}

// MARK: - Confidence Meter

struct ConfidenceMeter: View {
    let value: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: geo.size.width * value)
            }
        }
    }

    private var color: Color {
        if value >= 0.7 { return .green }
        if value >= 0.4 { return .orange }
        return .red
    }
}

// MARK: - Layer Group

struct LayerGroupView: View {
    let layer:      ArchLayer
    let files:      [FileLayerInfo]
    let isSelected: Bool
    let onTap:      () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 헤더
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: layer.icon)
                        .font(.body)
                        .foregroundColor(isSelected ? .white : .accentColor)
                        .frame(width: 18)
                    Text(layer.rawValue)
                        .font(.body).fontWeight(.semibold)
                    Spacer()
                    Text("\(files.count)개")
                        .font(.body)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.body)
                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            // 파일 목록 (펼쳐졌을 때)
            if isSelected {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(files) { info in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(complexityColor(info.file.complexityLevel))
                                .frame(width: 6, height: 6)
                            Text(info.file.fileName)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                            Spacer()
                            if let reason = info.reasons.first {
                                Text(reason)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 6)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    private func complexityColor(_ level: ComplexityLevel) -> Color {
        switch level {
        case .low:      return .green
        case .medium:   return .yellow
        case .high:     return .orange
        case .veryHigh: return .red
        }
    }
}

// MARK: - Issue Row

struct ArchIssueRow: View {
    let issue: ArchIssue
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(severityColor)
                        .frame(width: 4)

                    Image(systemName: issue.type.icon)
                        .font(.body)
                        .foregroundColor(severityColor)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.fileName)
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Text(issue.type.rawValue)
                            .font(.body).foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(issue.severity.rawValue)
                        .font(.body)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(severityColor.opacity(0.15))
                        .foregroundColor(severityColor)
                        .cornerRadius(4)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.body).foregroundColor(.secondary)
                }
                .padding(.vertical, 8).padding(.trailing, 12)
                .background(Color(.controlBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()

                    Label(issue.description, systemImage: "info.circle")
                        .font(.body).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        Label("수정 방법", systemImage: "lightbulb")
                            .font(.body).fontWeight(.semibold)
                            .foregroundColor(.yellow)
                        Text(issue.suggestion)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.yellow.opacity(0.08))
                            .cornerRadius(6)
                    }

                    // 프롬프트 복사 버튼
                    ArchCopyPromptButton(issue: issue)

                    Text(issue.filePath)
                        .font(.body).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.horizontal, 12).padding(.bottom, 12)
                .background(Color(.textBackgroundColor))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private var severityColor: Color {
        switch issue.severity {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .yellow
        }
    }
}

// MARK: - Copy Prompt Button (Architecture)

struct ArchCopyPromptButton: View {
    let issue: ArchIssue
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
            .font(.body).fontWeight(.semibold)
            .foregroundColor(copied ? .green : .accentColor)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private func makePrompt() -> String {
        """
        다음 Swift 파일의 아키텍처 문제를 수정해줘.

        파일: \(issue.filePath)
        이슈 유형: \(issue.type.rawValue) [\(issue.severity.rawValue) 심각도]

        문제 설명:
        \(issue.description)

        수정 방법:
        \(issue.suggestion)
        """
    }
}

// MARK: - BulkArchPromptButton

fileprivate struct BulkArchPromptButton: View {
    let issues: [ArchIssue]
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
                copied ? "복사됨!" : "전체 복사",
                systemImage: copied ? "checkmark.circle.fill" : "doc.on.clipboard"
            )
            .font(.body).fontWeight(.semibold)
            .foregroundColor(copied ? .green : .accentColor)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private func makePrompt() -> String {
        let issueList = issues.enumerated().map { i, issue in
            let sev = issue.severity == .high ? "🔴 높음" : issue.severity == .medium ? "🟠 중간" : "🟡 낮음"
            return """
            \(i + 1). [\(sev)] \(issue.type.rawValue) — \(issue.fileName)
               문제: \(issue.description)
               방향: \(issue.suggestion)
               파일: \(issue.filePath)
            """
        }.joined(separator: "\n\n")

        return """
        아래는 Swift 프로젝트의 아키텍처 분석 결과입니다 (\(issues.count)개).
        각 항목이 실제 문제인지 판단하고, 개선 방향을 간단히 제안해주세요.
        수정 코드는 필요 없고, 방향만 알려주세요.

        \(issueList)
        """
    }
}

// MARK: - ArchIssue.IssueType Hashable

extension ArchIssue.IssueType: Hashable {}
