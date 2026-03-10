import SwiftUI

// MARK: - DependencyView (관계도 + 분석 통합 탭)

struct DependencyView: View {

    let analyses:    [FileAnalysis]
    let edges:       [DependencyEdge]
    let healthScore: HealthScore?

    @State private var mode: Mode = .graph

    enum Mode: String, CaseIterable {
        case graph    = "관계도"
        case analysis = "의존성 분석"
    }

    var body: some View {
        VStack(spacing: 0) {
            // 상단 모드 전환
            HStack {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.windowBackgroundColor))

            Divider()

            switch mode {
            case .graph:
                GraphView(analyses: analyses, edges: edges)
            case .analysis:
                DependencyAnalysisPanel(analyses: analyses, edges: edges, healthScore: healthScore)
            }
        }
    }
}

// MARK: - DependencyAnalysisPanel

private struct DependencyAnalysisPanel: View {

    let analyses:    [FileAnalysis]
    let edges:       [DependencyEdge]
    let healthScore: HealthScore?

    @State private var stats: DependencyStats? = nil
    @State private var expandedSection: Section? = .cyclic

    enum Section { case cyclic, hub, fragile, edges }

    var body: some View {
        Group {
            if let stats {
                ScrollView {
                    VStack(spacing: 12) {
                        scoreBanner(stats: stats)
                        cyclicSection(stats: stats)
                        hubSection(stats: stats)
                        fragileSection(stats: stats)
                        edgesSection(stats: stats)
                    }
                    .padding(16)
                }
            } else {
                ProgressView("의존성 분석 중…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            guard stats == nil else { return }
            let a = analyses, e = edges
            Task.detached(priority: .userInitiated) {
                let s = DependencyStats.compute(analyses: a, edges: e)
                await MainActor.run { stats = s }
            }
        }
    }

    // MARK: - Score Banner

    private func scoreBanner(stats: DependencyStats) -> some View {
        let score = healthScore?.dependencyComponent
        let cyclicCount = stats.cyclicNodes.count
        return HStack(spacing: 20) {
            // 의존성 점수
            if let score {
                VStack(alignment: .leading, spacing: 2) {
                    Text("의존성 점수")
                        .font(.body).foregroundColor(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", score))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(healthColor(score))
                        Text("/ 100").font(.title3).foregroundColor(.secondary)
                    }
                }
                Divider().frame(height: 44)
            }

            statCell("총 의존 관계",  "\(stats.totalEdges)개",        "arrow.left.arrow.right", .blue)
            statCell("순환 의존성",   "\(cyclicCount)개 파일",         "exclamationmark.triangle",
                     cyclicCount > 0 ? .red : .green)
            statCell("고아 파일",     "\(stats.orphanedFilePaths.count)개", "xmark.circle", .secondary)

            if let top = stats.mostReferenced,
               let name = analyses.first(where: { $0.filePath == top.path })?.fileName {
                Divider().frame(height: 44)
                statCell("가장 많이 참조됨", "\(name) (\(top.count)회)", "star.fill", .yellow)
            }

            Spacer()

            // 가이드
            VStack(alignment: .trailing, spacing: 2) {
                Text("높을수록 의존 구조가 건강함").font(.caption).foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Label("75↑ 양호", systemImage: "circle.fill").foregroundColor(.green)
                    Label("50↑ 주의", systemImage: "circle.fill").foregroundColor(.orange)
                    Label("50↓ 위험", systemImage: "circle.fill").foregroundColor(.red)
                }
                .font(.caption2)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background((score.map { healthColor($0) } ?? .secondary).opacity(0.07))
        .cornerRadius(10)
    }

    private func statCell(_ label: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color).font(.body)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).foregroundColor(.secondary)
                Text(value).font(.callout).fontWeight(.semibold)
            }
        }
    }

    // MARK: - Cyclic Dependencies

    private func cyclicSection(stats: DependencyStats) -> some View {
        let cyclic = analyses.filter { stats.cyclicNodes.contains($0.filePath) }
        return sectionCard(
            title: "순환 의존성",
            subtitle: cyclic.isEmpty ? "없음 ✓" : "\(cyclic.count)개 파일이 순환에 포함됨",
            icon: "exclamationmark.triangle.fill",
            color: cyclic.isEmpty ? .green : .red,
            sectionKey: .cyclic
        ) {
            if cyclic.isEmpty {
                Label("순환 의존성이 없습니다. 의존 구조가 건강합니다.", systemImage: "checkmark.seal.fill")
                    .foregroundColor(.green).font(.callout).padding(.vertical, 4)
            } else {
                ForEach(cyclic) { file in
                    cyclicRow(file: file, stats: stats)
                }
                Text("해결 방법: 프로토콜로 의존성을 역전하거나, 공통 모델을 별도 파일로 분리하세요.")
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func cyclicRow(file: FileAnalysis, stats: DependencyStats) -> some View {
        let outFiles = edges
            .filter { $0.fromFilePath == file.filePath && stats.cyclicNodes.contains($0.toFilePath) }
            .compactMap { analyses.first(where: { $0.filePath == $0.filePath })?.fileName ?? URL(fileURLWithPath: $0.toFilePath).lastPathComponent }

        let deps = edges
            .filter { $0.fromFilePath == file.filePath && stats.cyclicNodes.contains($0.toFilePath) }
            .compactMap { edge -> String? in
                analyses.first(where: { $0.filePath == edge.toFilePath })?.fileName
            }

        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.red).font(.caption)
                Text(file.fileName)
                    .font(.callout).fontWeight(.medium)
                    .foregroundColor(.red)
                Spacer()
                Text("In \(stats.inDegree[file.filePath] ?? 0) · Out \(stats.outDegree[file.filePath] ?? 0)")
                    .font(.caption).foregroundColor(.secondary)
            }
            if !deps.isEmpty {
                Text("↔ " + deps.joined(separator: ", "))
                    .font(.caption).foregroundColor(.secondary)
                    .padding(.leading, 18)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.red.opacity(0.05))
        .cornerRadius(6)
    }

    // MARK: - Hub Files (고 in-degree)

    private func hubSection(stats: DependencyStats) -> some View {
        let hubs = analyses
            .compactMap { a -> (FileAnalysis, Int)? in
                guard let deg = stats.inDegree[a.filePath], deg > 0 else { return nil }
                return (a, deg)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(10)

        return sectionCard(
            title: "허브 파일 (많이 참조됨)",
            subtitle: "변경 시 파급 효과가 큰 파일 — 신중하게 수정하세요",
            icon: "star.fill",
            color: .yellow,
            sectionKey: .hub
        ) {
            if hubs.isEmpty {
                Text("데이터 없음").font(.callout).foregroundColor(.secondary)
            } else {
                ForEach(hubs, id: \.0.id) { file, deg in
                    degreeRow(file: file, inDeg: deg, outDeg: stats.outDegree[file.filePath] ?? 0,
                              bar: Double(deg), maxBar: Double(hubs.first?.1 ?? 1),
                              barColor: .yellow, label: "\(deg)개 파일이 참조")
                }
            }
        }
    }

    // MARK: - Fragile Files (고 out-degree)

    private func fragileSection(stats: DependencyStats) -> some View {
        let fragile = analyses
            .compactMap { a -> (FileAnalysis, Int)? in
                guard let deg = stats.outDegree[a.filePath], deg > 0 else { return nil }
                return (a, deg)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(10)

        return sectionCard(
            title: "의존 많은 파일 (취약 파일)",
            subtitle: "다른 파일에 많이 의존할수록 외부 변경에 취약합니다",
            icon: "link.badge.plus",
            color: .orange,
            sectionKey: .fragile
        ) {
            if fragile.isEmpty {
                Text("데이터 없음").font(.callout).foregroundColor(.secondary)
            } else {
                ForEach(fragile, id: \.0.id) { file, deg in
                    degreeRow(file: file, inDeg: stats.inDegree[file.filePath] ?? 0, outDeg: deg,
                              bar: Double(deg), maxBar: Double(fragile.first?.1 ?? 1),
                              barColor: .orange, label: "\(deg)개 파일을 참조")
                }
            }
        }
    }

    // MARK: - All Edges Table

    private func edgesSection(stats: DependencyStats) -> some View {
        let sorted = edges.sorted { lhs, rhs in
            let ln = analyses.first(where: { $0.filePath == lhs.fromFilePath })?.fileName ?? ""
            let rn = analyses.first(where: { $0.filePath == rhs.fromFilePath })?.fileName ?? ""
            return ln < rn
        }

        return sectionCard(
            title: "전체 의존 관계 목록",
            subtitle: "\(edges.count)개 연결",
            icon: "arrow.left.arrow.right",
            color: .blue,
            sectionKey: .edges
        ) {
            VStack(spacing: 0) {
                // 헤더
                HStack {
                    Text("참조하는 파일").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("→").font(.caption).foregroundColor(.secondary).frame(width: 20)
                    Text("참조되는 파일").font(.caption).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    Text("공유 타입").font(.caption).foregroundColor(.secondary).frame(width: 100, alignment: .trailing)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(.controlBackgroundColor))

                Divider()

                ForEach(sorted) { edge in
                    let fromName = analyses.first(where: { $0.filePath == edge.fromFilePath })?.fileName ?? URL(fileURLWithPath: edge.fromFilePath).lastPathComponent
                    let toName   = analyses.first(where: { $0.filePath == edge.toFilePath   })?.fileName ?? URL(fileURLWithPath: edge.toFilePath).lastPathComponent
                    let isCyclic = stats.cyclicNodes.contains(edge.fromFilePath) && stats.cyclicNodes.contains(edge.toFilePath)

                    HStack {
                        Text(fromName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(isCyclic ? .red : .primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Image(systemName: isCyclic ? "arrow.triangle.2.circlepath" : "arrow.right")
                            .font(.caption2)
                            .foregroundColor(isCyclic ? .red : .secondary)
                            .frame(width: 20)
                        Text(toName)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(isCyclic ? .red : .blue)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                        Text(edge.sharedTypes.prefix(3).joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .frame(width: 100, alignment: .trailing)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(isCyclic ? Color.red.opacity(0.04) : Color.clear)

                    Divider().opacity(0.5)
                }
            }
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
        }
    }

    // MARK: - Shared Components

    private func degreeRow(file: FileAnalysis, inDeg: Int, outDeg: Int,
                           bar: Double, maxBar: Double,
                           barColor: Color, label: String) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.callout).fontWeight(.medium).lineLimit(1)
                Text(label)
                    .font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 바 그래프
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor.opacity(0.7))
                        .frame(width: geo.size.width * min(bar / maxBar, 1.0))
                }
            }
            .frame(width: 120, height: 6)

            Text("In \(inDeg) · Out \(outDeg)")
                .font(.caption).foregroundColor(.secondary).monospacedDigit()
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String, subtitle: String, icon: String, color: Color,
        sectionKey: Section,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 섹션 헤더
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expandedSection = (expandedSection == sectionKey) ? nil : sectionKey
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon).foregroundColor(color).font(.body)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title).font(.callout).fontWeight(.semibold)
                        Text(subtitle).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: expandedSection == sectionKey ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 섹션 내용
            if expandedSection == sectionKey {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    content()
                }
                .padding(12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func healthColor(_ value: Double) -> Color {
        if value >= 75 { return .green }
        if value >= 50 { return Color(red: 0.9, green: 0.6, blue: 0.0) }
        return .red
    }
}
