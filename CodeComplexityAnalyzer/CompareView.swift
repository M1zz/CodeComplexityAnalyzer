import SwiftUI
import Charts

struct CompareView: View {
    let snapshots: [ProjectSnapshot]
    let currentHealth: HealthScore?
    let selectedPath: String?
    let onUpdateNote: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    private var projectSnapshots: [ProjectSnapshot] {
        guard let path = selectedPath else { return snapshots }
        return snapshots.filter { $0.projectPath == path }
    }

    var body: some View {
        if projectSnapshots.isEmpty {
            emptyStateView
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if projectSnapshots.count >= 2 {
                        sparklineSection
                    }
                    snapshotListSection
                }
                .padding()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("비교 기록이 없습니다")
                .font(.title2)
                .fontWeight(.medium)
            Text("첫 분석 후 비교 기록이 쌓입니다\n두 번 이상 분석하면 변화를 추적할 수 있습니다")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Sparkline Chart

    private var sparklineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("건강 점수 추이")
                .font(.headline)

            if #available(macOS 13, *) {
                let sorted = projectSnapshots.sorted { $0.date < $1.date }
                Chart(sorted.indices, id: \.self) { i in
                    let snap = sorted[i]
                    LineMark(
                        x: .value("날짜", snap.date),
                        y: .value("점수", snap.healthScore)
                    )
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    PointMark(
                        x: .value("날짜", snap.date),
                        y: .value("점수", snap.healthScore)
                    )
                    .foregroundStyle(Color.accentColor)
                    .annotation(position: .top) {
                        Text(String(format: "%.0f", snap.healthScore))
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(shortDate(date))
                                    .font(.body)
                            }
                        }
                    }
                }
                .frame(height: 160)
                .padding()
                .background(Color(.controlBackgroundColor))
                .cornerRadius(10)
            }
        }
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

private struct SnapshotRow: View {
    let snapshot: ProjectSnapshot
    let previous: ProjectSnapshot?
    let onUpdateNote: (UUID, String) -> Void
    let onDelete: (UUID) -> Void

    @State private var noteText: String = ""
    @State private var isEditingNote = false
    @FocusState private var noteFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 헤더: 등급 + 점수 + 날짜 + 삭제
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

            // 5요소 delta
            if let prev = previous {
                HStack(spacing: 12) {
                    metricDelta("복잡도", snapshot.complexityScore,   prev.complexityScore)
                    metricDelta("의존성", snapshot.dependencyScore,   prev.dependencyScore)
                    metricDelta("메모리", snapshot.memoryScore,       prev.memoryScore)
                    metricDelta("품질",   snapshot.qualityScore,      prev.qualityScore)
                    metricDelta("아키텍처", snapshot.architectureScore, prev.architectureScore)
                }
                .padding(.leading, 4)
            }

            // 기본 지표
            HStack(spacing: 16) {
                metricItem("파일",     "\(snapshot.totalFiles)")
                metricItem("함수",     "\(snapshot.totalFunctions)")
                metricItem("평균복잡도", String(format: "%.1f", snapshot.averageComplexity))
                metricItem("메모리이슈", "\(snapshot.memoryIssueCount)")
            }
            .padding(.leading, 4)

            // 메모
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
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("취소") {
                        noteText = snapshot.note ?? ""
                        isEditingNote = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "note.text")
                        .foregroundColor(.secondary).font(.body)
                    if let note = snapshot.note, !note.isEmpty {
                        Text(note)
                            .font(.body).foregroundColor(.primary)
                    } else {
                        Text("메모 없음 — 탭하여 추가")
                            .font(.body).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        isEditingNote = true
                        noteFocused = true
                    } label: {
                        Image(systemName: "pencil").font(.body)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    isEditingNote = true
                    noteFocused = true
                }
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
                Text(String(format: "%.0f", previous))
                    .font(.body).foregroundColor(.secondary)
                Image(systemName: "arrow.right").font(.body).foregroundColor(.secondary)
                Text(String(format: "%.0f", current))
                    .font(.body).fontWeight(.semibold)
                if diff != 0 {
                    Image(systemName: diff > 0 ? "arrow.up" : "arrow.down")
                        .font(.body)
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
