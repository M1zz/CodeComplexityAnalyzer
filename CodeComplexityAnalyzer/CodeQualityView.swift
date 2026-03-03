import SwiftUI
import Charts

struct CodeQualityView: View {
    let report: CodeQualityReport

    @State private var searchText     = ""
    @State private var showOnlyIssues = false

    private var filtered: [FileQuality] {
        report.files.filter {
            (!showOnlyIssues || !$0.issues.isEmpty) &&
            (searchText.isEmpty || $0.file.fileName.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            scoreBanner
            Divider()
            HSplitView {
                listPanel.frame(minWidth: 420)
                chartsPanel.frame(minWidth: 260, maxWidth: 380)
            }
        }
    }

    // MARK: - Banner

    private var scoreBanner: some View {
        HStack(spacing: 24) {
            VStack(spacing: 2) {
                Text("종합 품질 점수").font(.caption2).foregroundColor(.secondary)
                Text(String(format: "%.0f", report.overallScore))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundColor(scoreColor(report.overallScore))
                Text("/ 100").font(.caption2).foregroundColor(.secondary)
            }

            Divider().frame(height: 50)

            metric("평균 주석", String(format: "%.1f%%", report.avgCommentRatio * 100), .blue)
            metric("평균 함수 길이", String(format: "%.1f줄", report.avgFunctionLen), .green)
            metric("테스트 파일", "\(report.testFileCount)개", .purple)
            metric("이슈 있는 파일", "\(report.files.filter { !$0.issues.isEmpty }.count)개", .orange)

            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(color)
        }
    }

    // MARK: - List Panel

    private var listPanel: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered) { fq in FileQualityRow(fq: fq) }
                }
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 10) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("파일 검색...", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8).background(Color(.textBackgroundColor)).cornerRadius(8).frame(width: 200)

            Toggle("이슈만", isOn: $showOnlyIssues).toggleStyle(.checkbox).font(.caption)
            Spacer()
            Text("\(filtered.count)개").font(.caption).foregroundColor(.secondary)
        }
        .padding(10).background(Color(.windowBackgroundColor))
    }

    // MARK: - Charts Panel

    private var chartsPanel: some View {
        ScrollView {
            VStack(spacing: 16) { scoreDistChart; commentRatioChart }
                .padding()
        }
        .background(Color(.controlBackgroundColor))
    }

    private var scoreBuckets: [(range: String, count: Int)] {
        let a = report.files.filter { $0.score >= 90 }.count
        let b = report.files.filter { $0.score >= 70 && $0.score < 90 }.count
        let c = report.files.filter { $0.score >= 50 && $0.score < 70 }.count
        let d = report.files.filter { $0.score < 50 }.count
        return [("90–100", a), ("70–89", b), ("50–69", c), ("0–49", d)].filter { $0.count > 0 }
    }

    private var scoreDistChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("점수 분포").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            let buckets = scoreBuckets
            Chart(buckets, id: \.range) { b in
                BarMark(x: .value("수", b.count), y: .value("범위", b.range))
                    .foregroundStyle(Color.blue.gradient)
                    .annotation(position: .trailing) {
                        Text("\(b.count)").font(.caption2).foregroundColor(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(buckets.count * 36 + 10))
        }
        .padding().background(Color(.windowBackgroundColor)).cornerRadius(10)
    }

    private var commentRatioChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("낮은 주석 비율 파일 Top 5")
                .font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            let top = report.files
                .filter { $0.file.lineCount > 50 }
                .sorted { $0.commentRatio < $1.commentRatio }
                .prefix(5)
            if top.isEmpty {
                Text("해당 파일 없음").font(.caption).foregroundColor(.secondary).padding()
            } else {
                Chart(top) { fq in
                    BarMark(
                        x: .value("비율", fq.commentRatio * 100),
                        y: .value("파일", fq.file.fileName)
                    )
                    .foregroundStyle(Color.orange.gradient)
                    .annotation(position: .trailing) {
                        Text(String(format: "%.1f%%", fq.commentRatio * 100))
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(top.count * 36 + 10))
            }
        }
        .padding().background(Color(.windowBackgroundColor)).cornerRadius(10)
    }

    private func scoreColor(_ s: Double) -> Color {
        s >= 80 ? .green : s >= 60 ? .orange : .red
    }
}

// MARK: - File Quality Row

struct FileQualityRow: View {
    let fq: FileQuality
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        Circle().stroke(Color.secondary.opacity(0.2), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: fq.score / 100)
                            .stroke(scoreColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(String(format: "%.0f", fq.score))
                            .font(.system(size: 10, weight: .bold))
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fq.file.fileName)
                            .font(.system(.body, design: .monospaced)).fontWeight(.medium)
                        if let first = fq.issues.first {
                            Text(first).font(.caption2).foregroundColor(.orange).lineLimit(1)
                        }
                    }

                    Spacer()

                    vBadge(String(format: "%.0f%%", fq.commentRatio * 100), "주석", .blue)
                    vBadge(String(format: "%.0f", fq.avgFunctionLength), "avg줄", .green)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !fq.issues.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    ForEach(fq.issues, id: \.self) { issue in
                        Label(issue, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundColor(.orange)
                    }
                    QualityCopyPromptButton(fq: fq)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
                .background(Color(.textBackgroundColor))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private func vBadge(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.callout).fontWeight(.semibold).foregroundColor(color)
            Text(label).font(.caption2).foregroundColor(.secondary)
        }.frame(width: 46)
    }

    private var scoreColor: Color {
        fq.score >= 80 ? .green : fq.score >= 60 ? .orange : .red
    }
}

// MARK: - QualityCopyPromptButton

fileprivate struct QualityCopyPromptButton: View {
    let fq: FileQuality
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
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(copied ? .green : .accentColor)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private func makePrompt() -> String {
        """
        다음 Swift 파일의 코드 품질 문제를 개선해줘.

        파일: \(fq.file.filePath)
        품질 점수: \(String(format: "%.0f", fq.score)) / 100
        평균 함수 길이: \(String(format: "%.1f", fq.avgFunctionLength))줄
        주석 비율: \(String(format: "%.1f%%", fq.commentRatio * 100))

        발견된 문제:
        \(fq.issues.map { "- \($0)" }.joined(separator: "\n"))
        """
    }
}
