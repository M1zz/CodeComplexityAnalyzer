import SwiftUI
import Charts

struct CompareView: View {
    let snapshots: [ProjectSnapshot]
    let currentHealth: HealthScore?
    let selectedPath: String?

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
                            .font(.caption2)
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
                                    .font(.caption2)
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
            Text("분석 기록")
                .font(.headline)

            let sorted = projectSnapshots.sorted { $0.date > $1.date }
            ForEach(Array(sorted.enumerated()), id: \.element.id) { i, snapshot in
                snapshotRow(snapshot: snapshot, previous: sorted.indices.contains(i + 1) ? sorted[i + 1] : nil)
            }
        }
    }

    private func snapshotRow(snapshot: ProjectSnapshot, previous: ProjectSnapshot?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                // 등급 배지
                Text(snapshot.grade)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(gradeColor(snapshot.grade))
                    .frame(width: 36, height: 36)
                    .background(gradeColor(snapshot.grade).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f점", snapshot.healthScore))
                        .font(.callout)
                        .fontWeight(.semibold)
                    Text(fullDate(snapshot.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let prev = previous {
                    let diff = snapshot.healthScore - prev.healthScore
                    HStack(spacing: 3) {
                        Image(systemName: diff >= 0 ? "arrow.up" : "arrow.down")
                        Text(String(format: "%+.0f", diff))
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(diff >= 0 ? .green : .red)
                }
            }

            if let prev = previous {
                HStack(spacing: 16) {
                    metricDelta(label: "복잡도", current: snapshot.complexityScore, previous: prev.complexityScore)
                    metricDelta(label: "의존성", current: snapshot.dependencyScore, previous: prev.dependencyScore)
                    metricDelta(label: "메모리", current: snapshot.memoryScore, previous: prev.memoryScore)
                    metricDelta(label: "품질", current: snapshot.qualityScore, previous: prev.qualityScore)
                }
                .padding(.leading, 4)
            }

            HStack(spacing: 16) {
                metricItem(label: "파일", value: "\(snapshot.totalFiles)")
                metricItem(label: "함수", value: "\(snapshot.totalFunctions)")
                metricItem(label: "평균복잡도", value: String(format: "%.1f", snapshot.averageComplexity))
                metricItem(label: "메모리이슈", value: "\(snapshot.memoryIssueCount)")
            }
            .padding(.leading, 4)
        }
        .padding(14)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func metricDelta(label: String, current: Double, previous: Double) -> some View {
        let diff = current - previous
        let isUp = diff >= 0
        return VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            HStack(spacing: 2) {
                Text(String(format: "%.0f", previous))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f", current))
                    .font(.caption2)
                    .fontWeight(.semibold)
                Image(systemName: isUp ? "arrow.up" : "arrow.down")
                    .font(.caption2)
                    .foregroundColor(isUp ? .green : .red)
            }
        }
    }

    private func metricItem(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
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

    private func fullDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "ko_KR")
        return f.string(from: date)
    }
}
