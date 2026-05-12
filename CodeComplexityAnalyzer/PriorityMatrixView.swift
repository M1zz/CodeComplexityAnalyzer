import SwiftUI
import Charts

// MARK: - Priority Matrix

struct PriorityMatrixView: View {

    let analyses: [FileAnalysis]
    let actionItems: [ActionItem]

    @State private var selectedPoint: MatrixPoint? = nil

    // MARK: - Data Model

    struct MatrixPoint: Identifiable {
        let id: UUID
        let fileName: String
        let filePath: String
        let effort: Double    // X  0–100  (higher = harder)
        let impact: Double    // Y  0–100  (higher = more gain)

        var quadrant: Quadrant {
            switch (effort < 50, impact >= 50) {
            case (true,  true):  return .quickWin
            case (false, true):  return .bigBet
            case (true,  false): return .monitor
            case (false, false): return .lowPriority
            }
        }
    }

    enum Quadrant: String, Hashable, CaseIterable {
        case quickWin    = "즉시 개선"
        case bigBet      = "전략적 개선"
        case monitor     = "현상 유지"
        case lowPriority = "후순위"

        var color: Color {
            switch self {
            case .quickWin:    return .green
            case .bigBet:      return .blue
            case .monitor:     return Color(.systemGray)
            case .lowPriority: return .orange
            }
        }
        var icon: String {
            switch self {
            case .quickWin:    return "bolt.fill"
            case .bigBet:      return "target"
            case .monitor:     return "eye"
            case .lowPriority: return "pause.circle"
            }
        }
        var description: String {
            switch self {
            case .quickWin:    return "쉽게 고치고 효과 큰 파일"
            case .bigBet:      return "복잡하지만 개선 효과 큰 파일"
            case .monitor:     return "이미 양호, 주기적 점검"
            case .lowPriority: return "복잡하지만 당장 이슈 없음"
            }
        }
    }

    // MARK: - Computed Matrix Data

    private var points: [MatrixPoint] {
        guard !analyses.isEmpty else { return [] }

        let itemsByFile: [String: [ActionItem]] = Dictionary(grouping: actionItems, by: { $0.filePath })

        let rawEfforts: [Double] = analyses.map { a in
            Double(a.cyclomaticComplexity) * 3.0
                + Double(a.lineCount) * 0.04
                + Double(a.functionCount) * 0.6
        }
        let maxEffort: Double = rawEfforts.max() ?? 1.0

        let rawImpacts: [Double] = analyses.map { a -> Double in
            let items = itemsByFile[a.filePath] ?? []
            return items.reduce(0.0) { $0 + $1.impactScore }
        }
        let maxImpact: Double = rawImpacts.max() ?? 1.0

        var result: [MatrixPoint] = []
        for (idx, analysis) in analyses.enumerated() {
            let effort = maxEffort > 0 ? (rawEfforts[idx] / maxEffort) * 100.0 : 0.0
            let impact = maxImpact > 0 ? (rawImpacts[idx] / maxImpact) * 100.0 : 0.0
            result.append(MatrixPoint(
                id: analysis.id,
                fileName: analysis.fileName,
                filePath: analysis.filePath,
                effort: effort,
                impact: impact
            ))
        }
        return result
    }

    private func pointsIn(_ q: Quadrant) -> [MatrixPoint] {
        points.filter { $0.quadrant == q }.sorted { $0.impact > $1.impact }
    }

    // MARK: - Body

    var body: some View {
        HSplitView {
            chartPanel.frame(minWidth: 480)
            fileListPanel.frame(minWidth: 220, maxWidth: 300)
        }
    }

    // MARK: - Chart Panel

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection.padding()
            Divider()
            chartSection.padding()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("개선 우선순위 매트릭스")
                .font(.headline)
            Text("X축: 개선 난이도 (복잡도 기반)  ·  Y축: 예상 개선 효과")
                .font(.callout)
                .foregroundColor(.secondary)
            legendRow
        }
    }

    private var legendRow: some View {
        HStack(spacing: 16) {
            ForEach(Quadrant.allCases, id: \.self) { q in
                HStack(spacing: 4) {
                    Image(systemName: q.icon).foregroundColor(q.color).font(.body)
                    Text(q.rawValue).font(.body).foregroundColor(q.color)
                }
            }
        }
    }

    private var chartSection: some View {
        ZStack {
            matrixChart
            quadrantLabels.allowsHitTesting(false)
        }
    }

    // Split the chart into its own property to help type checker
    private var matrixChart: some View {
        Chart {
            RuleMark(x: .value("mid", 50.0))
                .foregroundStyle(Color.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            RuleMark(y: .value("mid", 50.0))
                .foregroundStyle(Color.secondary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))

            ForEach(points) { point in
                let isSelected = selectedPoint?.id == point.id
                PointMark(
                    x: .value("난이도", point.effort),
                    y: .value("개선효과", point.impact)
                )
                .foregroundStyle(isSelected ? Color.primary : point.quadrant.color.opacity(0.75))
                .symbolSize(isSelected ? 220 : 70)
                .annotation(position: .top) {
                    if isSelected {
                        Text(point.fileName)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color(.windowBackgroundColor))
                            .cornerRadius(4)
                            .shadow(radius: 2)
                    }
                }
            }
        }
        .chartXScale(domain: 0...100)
        .chartYScale(domain: 0...100)
        .chartXAxisLabel("← 쉬움    난이도    어려움 →")
        .chartYAxisLabel("개선 효과")
        .chartOverlay { proxy in
            Color.clear.contentShape(Rectangle())
                .onTapGesture { location in
                    handleTap(proxy: proxy, at: location)
                }
        }
    }

    private var quadrantLabels: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                quadrantLabel(.quickWin).frame(maxWidth: .infinity, alignment: .leading)
                quadrantLabel(.bigBet).frame(maxWidth: .infinity, alignment: .trailing)
            }
            Spacer()
            HStack(spacing: 0) {
                quadrantLabel(.monitor).frame(maxWidth: .infinity, alignment: .leading)
                quadrantLabel(.lowPriority).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(8)
    }

    private func quadrantLabel(_ q: Quadrant) -> some View {
        VStack(spacing: 2) {
            Image(systemName: q.icon).font(.body).foregroundColor(q.color)
            Text(q.rawValue).font(.caption).fontWeight(.semibold).foregroundColor(q.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(q.color.opacity(0.08))
        .cornerRadius(8)
    }

    private func handleTap(proxy: ChartProxy, at location: CGPoint) {
        let x: Double? = proxy.value(atX: location.x)
        let y: Double? = proxy.value(atY: location.y)
        guard let x, let y else { return }

        let nearest = points.min { a, b in
            squaredDist(a, x, y) < squaredDist(b, x, y)
        }
        guard let nearest else { return }

        if squaredDist(nearest, x, y) < 15 * 15 {
            if selectedPoint?.id == nearest.id {
                openInXcode(nearest.filePath)
            } else {
                selectedPoint = nearest
            }
        } else {
            selectedPoint = nil
        }
    }

    // MARK: - File List Panel

    private var fileListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("파일 목록")
                    .font(.headline)
                Text("클릭 → 선택  ·  재클릭 → Xcode 열기")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Quadrant.allCases, id: \.self) { q in
                        let qPts = pointsIn(q)
                        if !qPts.isEmpty {
                            quadrantSection(q, pts: qPts)
                        }
                    }
                }
            }
        }
        .background(Color(.controlBackgroundColor))
    }

    private func quadrantSection(_ q: Quadrant, pts: [MatrixPoint]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: q.icon).foregroundColor(q.color).font(.body)
                Text(q.rawValue)
                    .font(.callout).fontWeight(.semibold).foregroundColor(q.color)
                Text("\(pts.count)")
                    .font(.body).foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 12)
            .padding(.bottom, 2)

            Text(q.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 6)

            ForEach(pts) { point in
                fileRow(point: point, quadrant: q)
            }

            Divider().padding(.top, 6)
        }
    }

    private func fileRow(point: MatrixPoint, quadrant: Quadrant) -> some View {
        let isSelected = selectedPoint?.id == point.id
        return Button {
            if isSelected {
                openInXcode(point.filePath)
            } else {
                selectedPoint = point
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(isSelected ? Color.primary : quadrant.color)
                    .frame(width: 7, height: 7)
                Text(point.fileName)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundColor(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func squaredDist(_ p: MatrixPoint, _ x: Double, _ y: Double) -> Double {
        (p.effort - x) * (p.effort - x) + (p.impact - y) * (p.impact - y)
    }
}
