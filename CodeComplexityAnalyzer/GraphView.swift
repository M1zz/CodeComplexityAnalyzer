import SwiftUI

// MARK: - GraphView

struct GraphView: View {
    let analyses: [FileAnalysis]
    let edges:    [DependencyEdge]

    @State private var positions:     [String: CGPoint] = [:]
    @State private var isLayoutReady  = false
    @State private var layoutSize:    CGSize = .zero

    // 줌 / 패닝
    @State private var zoom:      CGFloat = 1.0
    @State private var baseZoom:  CGFloat = 1.0
    @State private var panOffset: CGSize  = .zero
    @State private var basePan:   CGSize  = .zero

    // 선택
    @State private var selectedFilePath:        String?    = nil
    @State private var selTransitiveDeps:       Set<String> = []
    @State private var selTransitiveDependents: Set<String> = []

    // 분석 결과
    @State private var stats:       DependencyStats? = nil
    @State private var cyclicNodes: Set<String>      = []

    // ── 직접 연결 (1-hop) ──────────────────────────────────────────────────────
    private var directDeps: Set<String> {
        Set(edges.filter { $0.fromFilePath == selectedFilePath }.map { $0.toFilePath })
    }
    private var directDependents: Set<String> {
        Set(edges.filter { $0.toFilePath == selectedFilePath }.map { $0.fromFilePath })
    }
    private var nodeDegree: [String: Int] {
        var d = [String: Int]()
        for e in edges {
            d[e.fromFilePath, default: 0] += 1
            d[e.toFilePath,   default: 0] += 1
        }
        return d
    }

    // MARK: - body

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                graphCanvas
                if let sel = selectedFilePath,
                   let analysis = analyses.first(where: { $0.filePath == sel }) {
                    Divider()
                    infoSidebar(analysis: analysis)
                        .frame(width: 280)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedFilePath)

            Divider()
            statsBar
        }
        .onChange(of: selectedFilePath) { _, newVal in
            updateTransitiveSets(for: newVal)
        }
    }

    // MARK: - 그래프 캔버스

    private var graphCanvas: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.07, green: 0.08, blue: 0.13)

            GeometryReader { geo in
                ZStack {
                    if isLayoutReady {
                        // 배경: 탭 → 선택 해제, 드래그 → 패닝
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { selectedFilePath = nil }
                            .gesture(
                                DragGesture(minimumDistance: 8)
                                    .onChanged { v in
                                        panOffset = CGSize(
                                            width:  basePan.width  + v.translation.width,
                                            height: basePan.height + v.translation.height
                                        )
                                    }
                                    .onEnded { _ in basePan = panOffset }
                            )

                        // 엣지 + 순환 링 (Canvas, 히트 테스팅 없음)
                        Canvas { ctx, _ in
                            drawEdges(ctx: ctx)
                            drawCyclicRings(ctx: ctx)
                        }
                        .allowsHitTesting(false)

                        // 노드 (SwiftUI - 드래그/탭)
                        ForEach(analyses) { a in nodeView(analysis: a) }

                    } else {
                        VStack(spacing: 14) {
                            ProgressView().colorScheme(.dark)
                            Text("관계도 계산 중…")
                                .foregroundColor(.white.opacity(0.55))
                                .font(.callout)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .onAppear {
                    guard !isLayoutReady, !analyses.isEmpty else { return }
                    layoutSize = geo.size
                    computeAll(size: geo.size)
                }
                // 핀치-투-줌 (트랙패드)
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in zoom = (baseZoom * val).clamped(0.25, 4.0) }
                        .onEnded   { val in baseZoom = (baseZoom * val).clamped(0.25, 4.0) }
                )
            }

            overlayBar
        }
    }

    // MARK: - 좌표 변환 (논리 ↔ 화면)

    /// 논리 좌표 → 화면 좌표 (줌 + 패닝 적용)
    private func renderPos(_ logical: CGPoint) -> CGPoint {
        let cx = layoutSize.width  / 2
        let cy = layoutSize.height / 2
        return CGPoint(
            x: (logical.x - cx) * zoom + cx + panOffset.width,
            y: (logical.y - cy) * zoom + cy + panOffset.height
        )
    }

    /// 화면 좌표 → 논리 좌표 (역변환)
    private func logicalPos(_ screen: CGPoint) -> CGPoint {
        let cx = layoutSize.width  / 2
        let cy = layoutSize.height / 2
        return CGPoint(
            x: (screen.x - panOffset.width  - cx) / zoom + cx,
            y: (screen.y - panOffset.height - cy) / zoom + cy
        )
    }

    // MARK: - 엣지 그리기

    private func drawEdges(ctx: GraphicsContext) {
        let sel   = selectedFilePath
        let dDeps = directDeps
        let dDepe = directDependents

        for edge in edges {
            guard let lFrom = positions[edge.fromFilePath],
                  let lTo   = positions[edge.toFilePath] else { continue }

            let from  = renderPos(lFrom)
            let to    = renderPos(lTo)
            let fromR = nodeRadius(for: edge.fromFilePath) * zoom
            let toR   = nodeRadius(for: edge.toFilePath)   * zoom

            let bothCyclic = cyclicNodes.contains(edge.fromFilePath)
                          && cyclicNodes.contains(edge.toFilePath)

            let color: Color
            let width: CGFloat

            if let sel {
                if edge.fromFilePath == sel {
                    color = .blue.opacity(0.90);   width = 2.0
                } else if edge.toFilePath == sel {
                    color = .orange.opacity(0.85); width = 2.0
                } else if dDeps.contains(edge.fromFilePath) || dDepe.contains(edge.fromFilePath)
                       || dDeps.contains(edge.toFilePath)   || dDepe.contains(edge.toFilePath) {
                    color = .white.opacity(0.20);  width = 1.0
                } else {
                    color = .white.opacity(0.04);  width = 0.5
                }
            } else if bothCyclic {
                color = Color.red.opacity(0.55); width = 1.5
            } else {
                color = .white.opacity(0.12);    width = 1.0
            }

            drawArrow(ctx: ctx, from: from, to: to,
                      fromR: fromR, toR: toR, color: color, width: width)
        }
    }

    private func drawArrow(ctx: GraphicsContext,
                           from: CGPoint, to: CGPoint,
                           fromR: CGFloat, toR: CGFloat,
                           color: Color, width: CGFloat) {
        let dx = to.x - from.x, dy = to.y - from.y
        let dist = max(hypot(dx, dy), 1)
        let ux = dx / dist, uy = dy / dist

        let p1 = CGPoint(x: from.x + ux * (fromR + 2), y: from.y + uy * (fromR + 2))
        let p2 = CGPoint(x: to.x   - ux * (toR   + 5), y: to.y   - uy * (toR   + 5))

        // 선분이 너무 짧으면 스킵
        guard hypot(p2.x - p1.x, p2.y - p1.y) > 4 else { return }

        var line = Path()
        line.move(to: p1); line.addLine(to: p2)
        ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: width))

        let al: CGFloat = 7, aa: CGFloat = 0.42
        let angle = atan2(dy, dx)
        var arrow = Path()
        arrow.move(to: p2)
        arrow.addLine(to: CGPoint(x: p2.x - al * cos(angle - aa),
                                  y: p2.y - al * sin(angle - aa)))
        arrow.move(to: p2)
        arrow.addLine(to: CGPoint(x: p2.x - al * cos(angle + aa),
                                  y: p2.y - al * sin(angle + aa)))
        ctx.stroke(arrow, with: .color(color),
                   style: StrokeStyle(lineWidth: width, lineCap: .round))
    }

    private func drawCyclicRings(ctx: GraphicsContext) {
        for fp in cyclicNodes {
            guard let lPos = positions[fp] else { continue }
            let pos = renderPos(lPos)
            let r   = (nodeRadius(for: fp) + 6) * zoom
            let rect = CGRect(x: pos.x - r, y: pos.y - r, width: r * 2, height: r * 2)
            ctx.stroke(
                Path(ellipseIn: rect),
                with: .color(Color.red.opacity(0.65)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4])
            )
        }
    }

    // MARK: - 노드 뷰

    @ViewBuilder
    private func nodeView(analysis: FileAnalysis) -> some View {
        let fp    = analysis.filePath
        let lPos  = positions[fp] ?? CGPoint(x: -500, y: -500)
        let pos   = renderPos(lPos)
        let r     = nodeRadius(for: fp) * zoom
        let state = nodeState(fp: fp)
        let label = analysis.fileName.replacingOccurrences(of: ".swift", with: "")

        ZStack {
            Circle()
                .fill(nodeColor(analysis.complexityLevel, state: state))
                .overlay(ringOverlay(state))
                .shadow(color: shadowColor(state), radius: shadowRadius(state))

            Text(label)
                .font(.system(size: max(8, min(r * 0.40, 11)), design: .monospaced))
                .fontWeight(.semibold)
                .foregroundColor(.white.opacity(r > 14 ? 1 : 0))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: r * 1.85)
        }
        .frame(width: r * 2, height: r * 2)
        .opacity(state == .unrelated ? 0.10 : 1.0)
        .position(pos)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedFilePath = (selectedFilePath == fp ? nil : fp)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { positions[fp] = logicalPos($0.location) }
        )
    }

    // MARK: - 노드 상태 / 색상

    private enum NodeState {
        case selected, directDep, directDependent
        case transitiveDep, transitiveDependent
        case normal, unrelated
    }

    private func nodeState(fp: String) -> NodeState {
        guard let sel = selectedFilePath else { return .normal }
        if fp == sel                            { return .selected }
        if directDeps.contains(fp)              { return .directDep }
        if directDependents.contains(fp)        { return .directDependent }
        if selTransitiveDeps.contains(fp)       { return .transitiveDep }
        if selTransitiveDependents.contains(fp) { return .transitiveDependent }
        return .unrelated
    }

    private func nodeColor(_ level: ComplexityLevel, state: NodeState) -> Color {
        let base: Color
        switch level {
        case .low:      base = Color(red: 0.20, green: 0.75, blue: 0.40)
        case .medium:   base = Color(red: 0.85, green: 0.72, blue: 0.0)
        case .high:     base = Color(red: 0.95, green: 0.55, blue: 0.10)
        case .veryHigh: base = Color(red: 0.92, green: 0.22, blue: 0.22)
        }
        switch state {
        case .directDep, .directDependent:         return base.opacity(0.85)
        case .transitiveDep, .transitiveDependent: return base.opacity(0.50)
        default:                                   return base
        }
    }

    @ViewBuilder
    private func ringOverlay(_ state: NodeState) -> some View {
        switch state {
        case .selected:
            Circle().stroke(Color.white, lineWidth: 2.5)
        case .directDep:
            Circle().stroke(Color.blue, lineWidth: 2)
        case .directDependent:
            Circle().stroke(Color.orange, lineWidth: 2)
        case .transitiveDep:
            Circle().stroke(Color.blue.opacity(0.45), lineWidth: 1.5)
        case .transitiveDependent:
            Circle().stroke(Color.orange.opacity(0.45), lineWidth: 1.5)
        default:
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 0.8)
        }
    }

    private func shadowColor(_ state: NodeState) -> Color {
        switch state {
        case .selected:        return .white.opacity(0.55)
        case .directDep:       return .blue.opacity(0.65)
        case .directDependent: return .orange.opacity(0.65)
        default:               return .black.opacity(0.40)
        }
    }
    private func shadowRadius(_ state: NodeState) -> CGFloat {
        switch state {
        case .selected:                    return 16
        case .directDep, .directDependent: return 9
        default:                           return 5
        }
    }

    // MARK: - 오버레이 바

    private var overlayBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                legendGroup
                Spacer()
                selectionLegend
                if isLayoutReady {
                    zoomControls
                }
            }
            if isLayoutReady {
                Text("핀치: 줌  ·  배경 드래그: 이동  ·  노드 드래그: 위치 변경  ·  노드 클릭: 선택")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .padding(10)
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            // 줌 인/아웃 버튼
            Button { withAnimation { zoom = (zoom / 1.3).clamped(0.25, 4.0); baseZoom = zoom } }
            label: { Image(systemName: "minus.magnifyingglass").font(.body) }
            .buttonStyle(.bordered).controlSize(.mini).colorScheme(.dark)

            Text(String(format: "%.0f%%", zoom * 100))
                .font(.body).monospacedDigit()
                .foregroundColor(.white.opacity(0.75))
                .frame(width: 36)

            Button { withAnimation { zoom = (zoom * 1.3).clamped(0.25, 4.0); baseZoom = zoom } }
            label: { Image(systemName: "plus.magnifyingglass").font(.body) }
            .buttonStyle(.bordered).controlSize(.mini).colorScheme(.dark)

            // 줌/패닝 초기화
            Button {
                withAnimation(.spring(response: 0.4)) {
                    zoom = 1; baseZoom = 1; panOffset = .zero; basePan = .zero
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.body)
            }
            .buttonStyle(.bordered).controlSize(.mini).colorScheme(.dark)
            .help("줌/이동 초기화")

            // 레이아웃 재계산
            Button {
                isLayoutReady = false; positions = [:]
                computeAll(size: layoutSize)
            } label: {
                Label("재계산", systemImage: "arrow.clockwise").font(.body)
            }
            .buttonStyle(.bordered).controlSize(.small).colorScheme(.dark)
        }
    }

    private var legendGroup: some View {
        HStack(spacing: 10) {
            legendDot(Color(red: 0.20, green: 0.75, blue: 0.40), "낮음")
            legendDot(Color(red: 0.85, green: 0.72, blue: 0.00), "보통")
            legendDot(Color(red: 0.95, green: 0.55, blue: 0.10), "높음")
            legendDot(Color(red: 0.92, green: 0.22, blue: 0.22), "매우 높음")
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.ultraThinMaterial).cornerRadius(7)
    }

    private var selectionLegend: some View {
        HStack(spacing: 10) {
            ringLegend(.blue,              "직접 의존 →")
            ringLegend(.orange,            "← 직접 피의존")
            ringLegend(.red.opacity(0.65), "순환", dashed: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.ultraThinMaterial).cornerRadius(7)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.body).foregroundColor(.white.opacity(0.8))
        }
    }
    private func ringLegend(_ color: Color, _ label: String, dashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            Circle()
                .stroke(color, style: dashed
                    ? StrokeStyle(lineWidth: 1.5, dash: [3, 2])
                    : StrokeStyle(lineWidth: 1.5))
                .frame(width: 10, height: 10)
            Text(label).font(.body).foregroundColor(.white.opacity(0.8))
        }
    }

    // MARK: - 통계 바

    private var statsBar: some View {
        HStack(spacing: 20) {
            if let s = stats {
                statChip(icon: "arrow.left.arrow.right", label: "총 의존 관계",
                         value: "\(s.totalEdges)개", color: .blue)
                statChip(icon: "exclamationmark.triangle", label: "순환 의존성",
                         value: "\(s.cyclicNodes.count)개 파일",
                         color: s.cyclicNodes.isEmpty ? .secondary : .red)
                statChip(icon: "circle.slash", label: "독립 파일",
                         value: "\(s.isolatedFilePaths.count)개", color: .secondary)
                if let top = s.mostReferenced,
                   let name = analyses.first(where: { $0.filePath == top.path })?.fileName {
                    Divider().frame(height: 20)
                    statChip(icon: "star.fill", label: "가장 많이 참조됨",
                             value: "\(name) (\(top.count)회)", color: .yellow)
                }
            } else {
                Text("분석 중…").font(.body).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
    }

    private func statChip(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundColor(color).font(.body)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.body).foregroundColor(.secondary)
                Text(value).font(.body).fontWeight(.medium)
            }
        }
    }

    // MARK: - 정보 사이드바

    private func infoSidebar(analysis: FileAnalysis) -> some View {
        let fp       = analysis.filePath
        let isCyclic = cyclicNodes.contains(fp)
        let inDeg    = stats?.inDegree[fp]  ?? 0
        let outDeg   = stats?.outDegree[fp] ?? 0
        let depList  = dependencyList(for: fp)

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.fileName)
                        .font(.system(.headline, design: .monospaced)).lineLimit(2)
                    Text(analysis.filePath)
                        .font(.body).foregroundColor(.secondary).lineLimit(4)
                }

                if isCyclic {
                    Label("순환 의존성 포함", systemImage: "exclamationmark.triangle.fill")
                        .font(.body).foregroundColor(.red)
                        .padding(6)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }

                Divider()

                HStack {
                    Circle().fill(complexityColor(analysis.complexityLevel))
                        .frame(width: 10, height: 10)
                    Text(analysis.complexityLevel.rawValue).font(.body)
                    Spacer()
                    Text(String(format: "%.1f", analysis.complexityScore)).fontWeight(.bold)
                }

                Group {
                    infoRow("라인 수",     "\(analysis.lineCount)")
                    infoRow("함수 수",     "\(analysis.functionCount)")
                    infoRow("순환 복잡도", "\(analysis.cyclomaticComplexity)")
                }

                Divider()

                Group {
                    infoRow("참조하는 파일 수 →", "\(outDeg)개")
                    infoRow("참조되는 파일 수 ←", "\(inDeg)개")
                    infoRow("전이적 의존 파일",   "\(selTransitiveDeps.count)개")
                    infoRow("전이적 피의존 파일", "\(selTransitiveDependents.count)개")
                }

                Divider()

                if !depList.uses.isEmpty {
                    Text("이 파일이 참조 (\(depList.uses.count))")
                        .font(.body).foregroundColor(.secondary).fontWeight(.semibold)
                    ForEach(depList.uses, id: \.fileName) { dep in
                        DepRowView(fileName: dep.fileName, types: dep.sharedTypes, direction: .outgoing)
                    }
                }
                if !depList.usedBy.isEmpty {
                    Text("이 파일을 참조 (\(depList.usedBy.count))")
                        .font(.body).foregroundColor(.secondary).fontWeight(.semibold)
                    ForEach(depList.usedBy, id: \.fileName) { dep in
                        DepRowView(fileName: dep.fileName, types: dep.sharedTypes, direction: .incoming)
                    }
                }
                if depList.uses.isEmpty && depList.usedBy.isEmpty {
                    Label("연결된 파일 없음", systemImage: "circle.slash")
                        .font(.body).foregroundColor(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding()
        }
        .background(Color(.controlBackgroundColor))
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.body).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.body).fontWeight(.medium).monospacedDigit()
        }
    }

    private func complexityColor(_ level: ComplexityLevel) -> Color {
        switch level {
        case .low:      return Color(red: 0.20, green: 0.75, blue: 0.40)
        case .medium:   return Color(red: 0.85, green: 0.72, blue: 0.00)
        case .high:     return Color(red: 0.95, green: 0.55, blue: 0.10)
        case .veryHigh: return Color(red: 0.92, green: 0.22, blue: 0.22)
        }
    }

    // MARK: - 의존성 목록

    private struct DepInfo { let fileName: String; let sharedTypes: [String] }

    private func dependencyList(for fp: String) -> (uses: [DepInfo], usedBy: [DepInfo]) {
        let uses = edges
            .filter { $0.fromFilePath == fp }
            .compactMap { edge -> DepInfo? in
                guard let name = analyses.first(where: { $0.filePath == edge.toFilePath })?.fileName
                else { return nil }
                return DepInfo(fileName: name, sharedTypes: edge.sharedTypes)
            }
            .sorted { $0.fileName < $1.fileName }

        let usedBy = edges
            .filter { $0.toFilePath == fp }
            .compactMap { edge -> DepInfo? in
                guard let name = analyses.first(where: { $0.filePath == edge.fromFilePath })?.fileName
                else { return nil }
                return DepInfo(fileName: name, sharedTypes: edge.sharedTypes)
            }
            .sorted { $0.fileName < $1.fileName }

        return (uses, usedBy)
    }

    // MARK: - 헬퍼

    private func nodeRadius(for fp: String) -> CGFloat {
        let deg = nodeDegree[fp] ?? 0
        // 연결 수에 따라 크기 조정 (최소 18, 최대 48)
        return max(18, min(CGFloat(20 + deg * 4), 48))
    }

    // MARK: - 비동기 계산

    private func computeAll(size: CGSize) {
        let a = analyses, e = edges
        DispatchQueue.global(qos: .userInitiated).async {
            let s   = DependencyStats.compute(analyses: a, edges: e)
            let pos = Self.forceLayout(analyses: a, edges: e, in: size)
            DispatchQueue.main.async {
                stats         = s
                cyclicNodes   = s.cyclicNodes
                positions     = pos
                isLayoutReady = true
            }
        }
    }

    private func updateTransitiveSets(for fp: String?) {
        guard let fp else {
            selTransitiveDeps = []; selTransitiveDependents = []
            return
        }
        let e = edges
        DispatchQueue.global(qos: .userInitiated).async {
            let deps = DependencyAnalyzer.transitivelyReachable(from: fp, using: e)
            let depe = DependencyAnalyzer.transitivelyDependent(on: fp, using: e)
            DispatchQueue.main.async {
                selTransitiveDeps       = deps
                selTransitiveDependents = depe
            }
        }
    }

    // MARK: - 포스 다이렉티드 레이아웃 (충돌 감지 포함)

    private static func forceLayout(
        analyses: [FileAnalysis],
        edges: [DependencyEdge],
        in size: CGSize
    ) -> [String: CGPoint] {

        let count = analyses.count
        guard count > 0, size.width > 0, size.height > 0 else { return [:] }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let initR  = min(size.width, size.height) * 0.38

        // 노드별 반지름 (degree 기반)
        var degMap = [String: Int]()
        for e in edges {
            degMap[e.fromFilePath, default: 0] += 1
            degMap[e.toFilePath,   default: 0] += 1
        }
        let radii: [String: CGFloat] = Dictionary(uniqueKeysWithValues: analyses.map { a in
            let deg = degMap[a.filePath] ?? 0
            return (a.filePath, max(18, min(CGFloat(20 + deg * 4), 48)))
        })

        // 원형 초기 배치 + 랜덤 지터 (대칭 깨기)
        var pos = [String: CGPoint]()
        for (i, a) in analyses.enumerated() {
            let angle  = 2 * CGFloat.pi * CGFloat(i) / CGFloat(max(count, 1))
            let jitter = CGFloat.random(in: -20...20)
            pos[a.filePath] = CGPoint(
                x: center.x + (initR + jitter) * cos(angle),
                y: center.y + (initR + jitter) * sin(angle)
            )
        }
        guard count > 1 else { return pos }

        let pairs = edges.map { ($0.fromFilePath, $0.toFilePath) }
        let keys  = Array(pos.keys)
        var vel   = [String: CGPoint](uniqueKeysWithValues: keys.map { ($0, CGPoint.zero) })

        // ── 파라미터 ───────────────────────────────────────────────────────────
        let repulsion: CGFloat = 28_000  // (이전: 6500) 반발력 대폭 증가
        let springLen: CGFloat = 230     // (이전: 155)  스프링 자연 길이 증가
        let springK:   CGFloat = 0.007   // 스프링 상수
        let damping:   CGFloat = 0.80    // 감쇠
        let minGap:    CGFloat = 18      // 노드 간 최소 여백
        let iters      = min(600, max(300, count * 10))

        for iter in 0..<iters {
            var f = [String: CGPoint](uniqueKeysWithValues: keys.map { ($0, CGPoint.zero) })

            // 1. 쌍별 반발력 (쿨롱 법칙)
            for i in 0..<keys.count {
                for j in (i + 1)..<keys.count {
                    let a = keys[i], b = keys[j]
                    guard let pa = pos[a], let pb = pos[b] else { continue }
                    let dx = pa.x - pb.x, dy = pa.y - pb.y
                    let d  = max(hypot(dx, dy), 1)
                    let fr = repulsion / (d * d)
                    let fx = fr * dx / d, fy = fr * dy / d
                    if var fa = f[a] { fa.x += fx; fa.y += fy; f[a] = fa }
                    if var fb = f[b] { fb.x -= fx; fb.y -= fy; f[b] = fb }
                }
            }

            // 2. 엣지 스프링 인력 (훅 법칙)
            for (from, to) in pairs {
                guard let pa = pos[from], let pb = pos[to] else { continue }
                let dx = pb.x - pa.x, dy = pb.y - pa.y
                let d  = max(hypot(dx, dy), 1)
                let fa = springK * (d - springLen)
                let fx = fa * dx / d, fy = fa * dy / d
                if var ff = f[from] { ff.x += fx; ff.y += fy; f[from] = ff }
                if var ft = f[to]   { ft.x -= fx; ft.y -= fy; f[to]   = ft }
            }

            // 3. 중심 인력 (초기엔 강하게, 점점 약하게)
            let grav = CGFloat(0.005) * (1.0 - CGFloat(iter) / CGFloat(iters))
            for key in keys {
                guard let p = pos[key] else { continue }
                if var fi = f[key] {
                    fi.x += (center.x - p.x) * grav
                    fi.y += (center.y - p.y) * grav
                    f[key] = fi
                }
            }

            // 4. 속도 통합 + 경계 클램핑
            for key in keys {
                guard let fi = f[key], let vi = vel[key], let pi = pos[key] else { continue }
                let ra  = (radii[key] ?? 20) + 8
                let nv  = CGPoint(x: (vi.x + fi.x) * damping,
                                  y: (vi.y + fi.y) * damping)
                vel[key] = nv
                pos[key] = CGPoint(
                    x: max(ra, min(size.width  - ra, pi.x + nv.x)),
                    y: max(ra, min(size.height - ra, pi.y + nv.y))
                )
            }

            // 5. 충돌 해소 — 겹친 노드를 서로 밀어냄 (핵심 개선)
            let collisionPasses = iter < iters / 2 ? 3 : 1
            for _ in 0..<collisionPasses {
                for i in 0..<keys.count {
                    for j in (i + 1)..<keys.count {
                        let a = keys[i], b = keys[j]
                        guard let pa = pos[a], let pb = pos[b] else { continue }
                        let dx = pa.x - pb.x, dy = pa.y - pb.y
                        let d  = max(hypot(dx, dy), 0.01)
                        let ra = radii[a] ?? 20
                        let rb = radii[b] ?? 20
                        let minDist = ra + rb + minGap
                        guard d < minDist else { continue }

                        // 겹친 만큼 양쪽으로 동등하게 밀어냄
                        let push = (minDist - d) * 0.5 + 0.5
                        let nx = dx / d * push, ny = dy / d * push
                        let raa = ra + 8, rbb = rb + 8

                        if var pa2 = pos[a] {
                            pa2.x = max(raa, min(size.width  - raa, pa2.x + nx))
                            pa2.y = max(raa, min(size.height - raa, pa2.y + ny))
                            pos[a] = pa2
                        }
                        if var pb2 = pos[b] {
                            pb2.x = max(rbb, min(size.width  - rbb, pb2.x - nx))
                            pb2.y = max(rbb, min(size.height - rbb, pb2.y - ny))
                            pos[b] = pb2
                        }
                    }
                }
            }
        }

        return pos
    }
}

// MARK: - CGFloat 클램프 헬퍼

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        Swift.max(lo, Swift.min(hi, self))
    }
}

// MARK: - 의존 행 뷰 (공유 타입 토글)

private struct DepRowView: View {
    enum Direction { case outgoing, incoming }

    let fileName:  String
    let types:     [String]
    let direction: Direction

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: direction == .outgoing ? "arrow.right" : "arrow.left")
                        .font(.body)
                        .foregroundColor(direction == .outgoing ? .blue : .orange)
                    Text(fileName)
                        .font(.body)
                        .foregroundColor(direction == .outgoing ? .blue : .orange)
                        .lineLimit(1)
                    Spacer()
                    if !types.isEmpty {
                        Text("\(types.count)개 타입")
                            .font(.body).foregroundColor(.secondary)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.body).foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if expanded && !types.isEmpty {
                ForEach(types, id: \.self) { t in
                    Text("• \(t)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.leading, 14)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
