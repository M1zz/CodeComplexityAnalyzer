import SwiftUI
import Charts

// MARK: - ChartsView

struct ChartsView: View {
    let analyses: [FileAnalysis]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                barChartSection

                HStack(alignment: .top, spacing: 16) {
                    donutChartSection
                    scatterPlotSection
                }

                treemapSection
            }
            .padding()
        }
    }

    // MARK: - 1. 복잡도 바 차트 (Top 20)

    private var barChartSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("파일별 복잡도 점수 (Top 20)", systemImage: "chart.bar.xaxis")
                    .font(.headline)

                let top = Array(analyses.prefix(20))

                Chart(top) { item in
                    BarMark(
                        x: .value("복잡도", item.complexityScore),
                        y: .value("파일", item.fileName.replacingOccurrences(of: ".swift", with: ""))
                    )
                    .foregroundStyle(colorFor(item.complexityLevel))
                    .cornerRadius(3)
                }
                .chartXAxisLabel("복잡도 점수")
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 10, design: .monospaced))
                    }
                }
                .frame(height: CGFloat(max(top.count, 3)) * 30 + 50)
            }
        }
    }

    // MARK: - 2. 복잡도 레벨 도넛 차트

    private var donutChartSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("복잡도 레벨 분포", systemImage: "chart.pie.fill")
                    .font(.headline)

                let dist = levelDistribution()

                Chart(dist, id: \.name) { item in
                    SectorMark(
                        angle: .value("파일 수", item.count),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(colorByName(item.name))
                }
                .frame(height: 200)

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(dist, id: \.name) { item in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(colorByName(item.name))
                                .frame(width: 12, height: 12)
                            Text(item.name)
                                .font(.caption)
                            Spacer()
                            Text("\(item.count)개")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 3. 라인 수 vs 순환 복잡도 산점도

    private var scatterPlotSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("라인 수 vs 순환 복잡도", systemImage: "chart.xyaxis.line")
                    .font(.headline)

                Chart(analyses) { item in
                    PointMark(
                        x: .value("라인 수", item.lineCount),
                        y: .value("순환 복잡도", item.cyclomaticComplexity)
                    )
                    .foregroundStyle(colorFor(item.complexityLevel).opacity(0.8))
                    .symbolSize(80)
                }
                .chartXAxisLabel("라인 수")
                .chartYAxisLabel("순환 복잡도")
                .frame(height: 270)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. 트리맵

    private var treemapSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("파일 복잡도 트리맵", systemImage: "square.grid.2x2")
                    .font(.headline)

                Text("크기 = 복잡도 점수  |  색상 = 복잡도 레벨")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TreemapView(analyses: analyses)
                    .frame(height: 440)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Helpers

    private func levelDistribution() -> [(name: String, count: Int)] {
        ComplexityLevel.allCases.compactMap { level in
            let count = analyses.filter { $0.complexityLevel == level }.count
            return count > 0 ? (name: level.rawValue, count: count) : nil
        }
    }

    private func colorFor(_ level: ComplexityLevel) -> Color {
        switch level {
        case .low:      return .green
        case .medium:   return Color(red: 0.85, green: 0.75, blue: 0.0)
        case .high:     return .orange
        case .veryHigh: return .red
        }
    }

    private func colorByName(_ name: String) -> Color {
        switch name {
        case ComplexityLevel.low.rawValue:      return .green
        case ComplexityLevel.medium.rawValue:   return Color(red: 0.85, green: 0.75, blue: 0.0)
        case ComplexityLevel.high.rawValue:     return .orange
        case ComplexityLevel.veryHigh.rawValue: return .red
        default:                                return .gray
        }
    }
}

// MARK: - TreemapView

struct TreemapView: View {
    let analyses: [FileAnalysis]

    private struct LayoutItem: Identifiable {
        let analysis: FileAnalysis
        let rect: CGRect
        var id: UUID { analysis.id }
    }

    var body: some View {
        GeometryReader { geo in
            let sorted = analyses
                .filter { $0.complexityScore > 0 }
                .sorted { $0.complexityScore > $1.complexityScore }
            let items = buildTreemap(
                from: sorted,
                in: CGRect(origin: .zero, size: geo.size)
            )

            ZStack {
                // 배경 직사각형 (Canvas)
                Canvas { context, _ in
                    for item in items {
                        let inset = item.rect.insetBy(dx: 1.5, dy: 1.5)
                        guard inset.width > 0, inset.height > 0 else { continue }
                        let path = Path(roundedRect: inset, cornerRadius: 3)
                        context.fill(path, with: .color(colorFor(item.analysis.complexityLevel).opacity(0.85)))
                        context.stroke(
                            Path(roundedRect: inset, cornerRadius: 3),
                            with: .color(.white.opacity(0.25)),
                            lineWidth: 0.5
                        )
                    }
                }

                // 파일 이름 레이블
                ForEach(items) { item in
                    if item.rect.width > 45 && item.rect.height > 25 {
                        let fontSize: CGFloat = min(max(item.rect.width / 9.0, 7.0), 12.0)
                        VStack(spacing: 1) {
                            Text(item.analysis.fileName.replacingOccurrences(of: ".swift", with: ""))
                                .font(.system(size: fontSize, design: .monospaced))
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            if item.rect.height > 45 {
                                Text(String(format: "%.0f", item.analysis.complexityScore))
                                    .font(.system(size: max(fontSize - 2.0, 7.0)))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 2)
                        .frame(width: item.rect.width - 4, height: item.rect.height - 4, alignment: .center)
                        .clipped()
                        .position(x: item.rect.midX, y: item.rect.midY)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    // 이진 분할 트리맵 레이아웃
    private func buildTreemap(from items: [FileAnalysis], in rect: CGRect) -> [LayoutItem] {
        guard !items.isEmpty, rect.width > 0, rect.height > 0 else { return [] }
        guard items.count > 1 else { return [LayoutItem(analysis: items[0], rect: rect)] }

        let total = items.reduce(0.0) { $0 + $1.complexityScore }
        guard total > 0 else { return [] }

        // 합이 전체의 절반에 가까운 분할점 탐색
        var cumulative = 0.0
        var splitIndex = 0
        for i in 0..<(items.count - 1) {
            cumulative += items[i].complexityScore
            splitIndex = i
            if cumulative / total >= 0.5 { break }
        }

        let firstItems  = Array(items[0...splitIndex])
        let secondItems = Array(items[(splitIndex + 1)...])
        let ratio = firstItems.reduce(0.0) { $0 + $1.complexityScore } / total

        let firstRect: CGRect
        let secondRect: CGRect

        if rect.width >= rect.height {
            let splitX = rect.minX + rect.width * CGFloat(ratio)
            firstRect  = CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width * CGFloat(ratio), height: rect.height)
            secondRect = CGRect(x: splitX,     y: rect.minY,
                                width: rect.width * CGFloat(1.0 - ratio), height: rect.height)
        } else {
            let splitY = rect.minY + rect.height * CGFloat(ratio)
            firstRect  = CGRect(x: rect.minX, y: rect.minY,
                                width: rect.width, height: rect.height * CGFloat(ratio))
            secondRect = CGRect(x: rect.minX, y: splitY,
                                width: rect.width, height: rect.height * CGFloat(1.0 - ratio))
        }

        return buildTreemap(from: firstItems,  in: firstRect)
             + buildTreemap(from: secondItems, in: secondRect)
    }

    private func colorFor(_ level: ComplexityLevel) -> Color {
        switch level {
        case .low:      return .green
        case .medium:   return Color(red: 0.85, green: 0.75, blue: 0.0)
        case .high:     return .orange
        case .veryHigh: return .red
        }
    }
}
