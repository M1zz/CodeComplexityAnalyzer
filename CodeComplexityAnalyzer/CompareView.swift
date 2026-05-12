import SwiftUI
import Charts

// MARK: - TrendView (CompareView)

struct CompareView: View {
    let snapshots: [ProjectSnapshot]
    let currentHealth: HealthScore?
    let selectedPath: String?
    let onUpdateNote: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @State private var visibleSeries: Set<TrendSeries> = Set(TrendSeries.allCases)

    // MARK: - Series Definition

    enum TrendSeries: String, CaseIterable, Identifiable, Hashable {
        case overall      = "전체"
        case complexity   = "복잡도"
        case dependency   = "의존성"
        case memory       = "메모리"
        case quality      = "품질"
        case architecture = "아키텍처"

        var id: String { rawValue }

        var color: Color {
            switch self {
            case .overall:      return .accentColor
            case .complexity:   return .orange
            case .dependency:   return .blue
            case .memory:       return .red
            case .quality:      return .green
            case .architecture: return .purple
            }
        }

        var lineWidth: CGFloat { self == .overall ? 2.5 : 1.5 }
        var symbolSize: CGFloat { self == .overall ? 55 : 28 }

        func value(from s: ProjectSnapshot) -> Double {
            switch self {
            case .overall:      return s.healthScore
            case .complexity:   return s.complexityScore
            case .dependency:   return s.dependencyScore
            case .memory:       return s.memoryScore
            case .quality:      return s.qualityScore
            case .architecture: return s.architectureScore
            }
        }
    }

    // MARK: - Filtered Snapshots

    private var projectSnapshots: [ProjectSnapshot] {
        let all = selectedPath.map { p in snapshots.filter { $0.projectPath == p } } ?? snapshots
        return all.sorted { $0.date < $1.date }
    }

    // MARK: - Body

    var body: some View {
        if projectSnapshots.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    trendChartSection
                    Divider()
                    snapshotListSection
                }
                .padding()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("분석 기록이 없습니다")
                .font(.title2)
                .fontWeight(.medium)
            Text("분석을 두 번 이상 실행하면\n지표 변화 추이를 확인할 수 있습니다")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Trend Chart

    private var trendChartSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("건강 지표 추이")
                        .font(.headline)
                    Text("\(projectSnapshots.count)회 분석 · 최근 30회 보관")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
                seriesToggleBar
            }

            // Multi-series chart
            Chart {
                ForEach(TrendSeries.allCases.filter { visibleSeries.contains($0) }) { series in
                    ForEach(projectSnapshots.indices, id: \.self) { idx in
                        let snap = projectSnapshots[idx]
                        LineMark(
                            x: .value("날짜", snap.date),
                            y: .value(series.rawValue, series.value(from: snap)),
                            series: .value("지표", series.rawValue)
                        )
                        .foregroundStyle(series.color)
                        .lineStyle(StrokeStyle(lineWidth: series.lineWidth))

                        PointMark(
                            x: .value("날짜", snap.date),
                            y: .value(series.rawValue, series.value(from: snap))
                        )
                        .foregroundStyle(series.color)
                        .symbolSize(series.symbolSize)
                    }
                }
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 25, 50, 75, 100]) { v in
                    AxisGridLine()
                    AxisValueLabel { Text("\(v.as(Int.self) ?? 0)") }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { v in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = v.as(Date.self) {
                            Text(shortDate(date)).font(.caption)
                        }
                    }
                }
            }
            .frame(height: 260)
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(10)

            // Delta summary (first → last)
            if projectSnapshots.count >= 2 {
                deltaSummaryRow
            }
        }
    }

    private var seriesToggleBar: some View {
        HStack(spacing: 6) {
            ForEach(TrendSeries.allCases) { series in
                Button {
                    if visibleSeries.contains(series) {
                        if visibleSeries.count > 1 { visibleSeries.remove(series) }
                    } else {
                        visibleSeries.insert(series)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(series.color)
                            .frame(width: 7, height: 7)
                        Text(series.rawValue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        visibleSeries.contains(series)
                            ? series.color.opacity(0.15)
                            : Color(.controlBackgroundColor)
                    )
                    .foregroundColor(
                        visibleSeries.contains(series) ? series.color : .secondary
                    )
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                visibleSeries.contains(series)
                                    ? series.color.opacity(0.4)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var deltaSummaryRow: some View {
        let first = projectSnapshots.first!
        let last  = projectSnapshots.last!
        let deltaSeries = TrendSeries.allCases.filter { visibleSeries.contains($0) }

        return HStack(spacing: 12) {
            Text("첫 분석 → 최근")
                .font(.body)
                .foregroundColor(.secondary)

            ForEach(deltaSeries) { series in
                let diff = series.value(from: last) - series.value(from: first)
                HStack(spacing: 3) {
                    Circle().fill(series.color).frame(width: 7, height: 7)
                    Text(series.rawValue)
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text(String(format: "%+.0f", diff))
                        .font(.body)
                        .fontWeight(.semibold)
                        .foregroundColor(diff >= 0 ? .green : .red)
                }
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Snapshot List

    private var snapshotListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("분석 기록")
                    .font(.headline)
                Text("(\(projectSnapshots.count)개)")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            let sorted = projectSnapshots.sorted { $0.date > $1.date }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, snapshot in
                SnapshotRow(
                    snapshot: snapshot,
                    previous: sorted.indices.contains(i + 1) ? sorted[i + 1] : nil,
                    onUpdateNote: onUpdateNote,
                    onDelete: onDelete
                )
            }
        }
    }

    // MARK: - Helpers

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .blue
        case "C": return .yellow
        case "D": return .orange
        default:  return .red
        }
    }

    private func shortDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}

// MARK: - SnapshotRow

struct SnapshotRow: View {
    let snapshot: ProjectSnapshot
    let previous: ProjectSnapshot?
    let onUpdateNote: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @State private var noteText: String = ""
    @State private var isEditingNote = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: grade + score + date + delete
            HStack {
                Text(snapshot.grade)
                    .font(.title2).fontWeight(.bold)
                    .foregroundColor(gradeColor(snapshot.grade))
                    .frame(width: 36, height: 36)
                    .background(gradeColor(snapshot.grade).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f점", snapshot.healthScore))
                        .font(.callout).fontWeight(.semibold)
                    Text(fullDate(snapshot.date))
                        .font(.body).foregroundColor(.secondary)
                }

                Spacer()

                if let prev = previous {
                    let diff = snapshot.healthScore - prev.healthScore
                    HStack(spacing: 3) {
                        Image(systemName: diff >= 0 ? "arrow.up" : "arrow.down")
                        Text(String(format: "%+.0f", diff))
                    }
                    .font(.body).fontWeight(.semibold)
                    .foregroundColor(diff >= 0 ? .green : .red)
                }

                Button(role: .destructive) {
                    onDelete(snapshot.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.body).foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)
            }

            // 5-component delta
            if let prev = previous {
                HStack(spacing: 12) {
                    metricDelta("복잡도",  snapshot.complexityScore,   prev.complexityScore)
                    metricDelta("의존성",  snapshot.dependencyScore,   prev.dependencyScore)
                    metricDelta("메모리",  snapshot.memoryScore,       prev.memoryScore)
                    metricDelta("품질",    snapshot.qualityScore,      prev.qualityScore)
                    metricDelta("아키텍처", snapshot.architectureScore, prev.architectureScore)
                }
                .padding(.leading, 4)
            }

            // Basic metrics
            HStack(spacing: 16) {
                metricItem("파일",      "\(snapshot.totalFiles)")
                metricItem("함수",      "\(snapshot.totalFunctions)")
                metricItem("평균복잡도", String(format: "%.1f", snapshot.averageComplexity))
                metricItem("메모리이슈", "\(snapshot.memoryIssueCount)")
            }
            .padding(.leading, 4)

            noteSection
        }
        .padding(14)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
        .onAppear { noteText = snapshot.note ?? "" }
    }

    // MARK: - Note

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            if isEditingNote {
                HStack(spacing: 8) {
                    Image(systemName: "pencil").foregroundColor(.accentColor).font(.body)
                    TextField("이번 분석에서 무엇을 고쳤나요?", text: $noteText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .focused($noteFocused)
                        .onSubmit { commitNote() }
                    Button("완료") { commitNote() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    Button("취소") {
                        noteText = snapshot.note ?? ""
                        isEditingNote = false
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "note.text").foregroundColor(.secondary).font(.body)
                    if let note = snapshot.note, !note.isEmpty {
                        Text(note).font(.body)
                    } else {
                        Text("메모 없음 — 탭하여 추가").font(.body).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        isEditingNote = true; noteFocused = true
                    } label: {
                        Image(systemName: "pencil").font(.body)
                    }
                    .buttonStyle(.plain).foregroundColor(.accentColor)
                }
                .contentShape(Rectangle())
                .onTapGesture { isEditingNote = true; noteFocused = true }
            }
        }
    }

    private func commitNote() {
        onUpdateNote(snapshot.id, noteText)
        isEditingNote = false
    }

    // MARK: - Helpers

    private func metricDelta(_ label: String, _ current: Double, _ previous: Double) -> some View {
        let diff = current - previous
        return VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.body).foregroundColor(.secondary)
            HStack(spacing: 2) {
                Text(String(format: "%.0f", previous)).font(.body).foregroundColor(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundColor(.secondary)
                Text(String(format: "%.0f", current)).font(.body).fontWeight(.semibold)
                if diff != 0 {
                    Image(systemName: diff > 0 ? "arrow.up" : "arrow.down")
                        .font(.caption)
                        .foregroundColor(diff > 0 ? .green : .red)
                }
            }
        }
    }

    private func metricItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.body).foregroundColor(.secondary)
            Text(value).font(.body).fontWeight(.medium)
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .blue
        case "C": return .yellow
        case "D": return .orange
        default:  return .red
        }
    }

    private func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "ko_KR")
        return f.string(from: date)
    }
}
