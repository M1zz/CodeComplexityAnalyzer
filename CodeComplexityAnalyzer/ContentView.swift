import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var viewModel = AnalyzerViewModel()
    @State private var selectedSort: SortOption = .complexity
    @State private var searchText = ""
    @State private var viewMode: ViewMode = .list
    
    enum SortOption: String, CaseIterable {
        case complexity = "복잡도"
        case lines = "라인 수"
        case functions = "함수 수"
        case name = "이름"
    }

    enum ViewMode: String, CaseIterable {
        case list         = "목록"
        case chart        = "차트"
        case graph        = "관계도"
        case memory       = "메모리"
        case architecture = "아키텍처"
        case quality      = "품질"
        case functions    = "함수"
        case gitHistory   = "변경이력"
        case todo         = "TODO"

        var icon: String {
            switch self {
            case .list:         return "list.bullet"
            case .chart:        return "chart.bar.xaxis"
            case .graph:        return "network"
            case .memory:       return "memorychip"
            case .architecture: return "building.columns"
            case .quality:      return "checkmark.seal"
            case .functions:    return "function"
            case .gitHistory:   return "clock.arrow.circlepath"
            case .todo:         return "checklist"
            }
        }
    }
    
    var filteredAndSortedAnalyses: [FileAnalysis] {
        var result = viewModel.analyses
        
        // 검색 필터
        if !searchText.isEmpty {
            result = result.filter { 
                $0.fileName.localizedCaseInsensitiveContains(searchText) 
            }
        }
        
        // 정렬
        switch selectedSort {
        case .complexity:
            result.sort { $0.complexityScore > $1.complexityScore }
        case .lines:
            result.sort { $0.lineCount > $1.lineCount }
        case .functions:
            result.sort { $0.functionCount > $1.functionCount }
        case .name:
            result.sort { $0.fileName < $1.fileName }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 헤더
            headerView

            Divider()

            // 요약 정보
            if let summary = viewModel.summary {
                summaryView(summary: summary)
                Divider()
            }

            // 상태별 분기
            if viewModel.isAnalyzing {
                analyzingView
            } else if viewModel.analyses.isEmpty {
                emptyStateView
            } else {
                // 뷰 모드 선택 바
                viewModeBar
                Divider()

                switch viewMode {
                case .list:
                    controlBar
                    Divider()
                    fileListView
                case .chart:
                    ChartsView(analyses: viewModel.analyses)
                case .graph:
                    GraphView(analyses: viewModel.analyses, edges: viewModel.dependencyEdges)
                case .memory:
                    MemoryLeakView(issues: viewModel.leakIssues)
                case .architecture:
                    if let report = viewModel.archReport {
                        ArchitectureView(report: report, analyses: viewModel.analyses)
                    } else {
                        ProgressView("아키텍처 분석 중...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .quality:
                    if let report = viewModel.qualityReport {
                        CodeQualityView(report: report)
                    } else {
                        ProgressView("품질 분석 중...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .functions:
                    FunctionView(functions: viewModel.functions)
                case .gitHistory:
                    if let report = viewModel.gitHistoryReport {
                        GitHistoryView(report: report)
                    } else {
                        ProgressView("변경 이력 분석 중...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                case .todo:
                    TodoView(items: viewModel.todoItems)
                }
            }
        }
        .frame(minWidth: 1100, minHeight: 650)
    }

    private var viewModeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Button {
                        viewMode = mode
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon).font(.caption)
                            Text(mode.rawValue)
                                .font(.caption)
                                .fontWeight(viewMode == mode ? .semibold : .regular)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(viewMode == mode ? Color.accentColor : Color.clear)
                        .foregroundColor(viewMode == mode ? .white : .primary)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(Color(.windowBackgroundColor))
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.title2)
                .foregroundColor(.blue)
            
            Text("코드 복잡도 분석기")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            if viewModel.selectedPath != nil {
                // 내보내기 메뉴 (분석 완료 후만 표시)
                if !viewModel.analyses.isEmpty {
                    Menu {
                        ForEach(ExportFormat.allCases) { fmt in
                            Button {
                                viewModel.exportReport(format: fmt)
                            } label: {
                                Label(fmt.rawValue, systemImage: fmt.icon)
                            }
                        }
                    } label: {
                        Label("내보내기", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                Button(action: { viewModel.selectFolder() }) {
                    Label("다른 폴더 선택", systemImage: "folder")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.windowBackgroundColor))
    }
    
    private func summaryView(summary: ProjectSummary) -> some View {
        HStack(spacing: 30) {
            summaryCard(
                title: "총 파일",
                value: "\(summary.totalFiles)",
                icon: "doc.text",
                color: .blue
            )
            
            summaryCard(
                title: "총 라인",
                value: NumberFormatter.localizedString(from: NSNumber(value: summary.totalLines), number: .decimal),
                icon: "text.alignleft",
                color: .green
            )
            
            summaryCard(
                title: "총 함수",
                value: "\(summary.totalFunctions)",
                icon: "function",
                color: .orange
            )
            
            summaryCard(
                title: "평균 복잡도",
                value: String(format: "%.1f", summary.averageComplexity),
                icon: "gauge",
                color: .purple
            )
            
            if let mostComplex = summary.mostComplexFile {
                VStack(alignment: .leading, spacing: 4) {
                    Label("가장 복잡한 파일", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(mostComplex.fileName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }
                .frame(maxWidth: 200, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
    }
    
    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
    }
    
    private var controlBar: some View {
        HStack {
            // 검색
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("파일 검색...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(.textBackgroundColor))
            .cornerRadius(8)
            .frame(width: 250)
            
            Spacer()
            
            // 정렬
            Picker("정렬", selection: $selectedSort) {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            
            // 결과 개수
            Text("\(filteredAndSortedAnalyses.count)개 파일")
                .foregroundColor(.secondary)
                .font(.caption)
        }
        .padding()
    }
    
    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredAndSortedAnalyses) { analysis in
                    FileRow(analysis: analysis)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("Xcode 프로젝트를 선택해주세요")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("프로젝트 폴더를 선택하면 Swift 파일들을 분석합니다")
                .foregroundColor(.secondary)
            
            Button(action: { viewModel.selectFolder() }) {
                Label("프로젝트 폴더 선택", systemImage: "folder")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var analyzingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("분석 중...")
                .font(.title2)
                .fontWeight(.medium)
            
            if let path = viewModel.selectedPath {
                Text(path)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FileRow: View {
    let analysis: FileAnalysis
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 메인 행
            Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                HStack(spacing: 12) {
                    // 복잡도 인디케이터
                    Circle()
                        .fill(complexityColor)
                        .frame(width: 12, height: 12)
                    
                    // 파일 이름
                    VStack(alignment: .leading, spacing: 2) {
                        Text(analysis.fileName)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                        
                        Text(analysis.filePath)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                    
                    // 주요 지표
                    metricBadge(value: "\(analysis.lineCount)", label: "lines", color: .blue)
                    metricBadge(value: "\(analysis.functionCount)", label: "funcs", color: .orange)
                    
                    // 복잡도 점수
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.1f", analysis.complexityScore))
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(complexityColor)
                        Text(analysis.complexityLevel.rawValue)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80, alignment: .trailing)
                    
                    // 확장 아이콘
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            
            // 상세 정보 (확장 시)
            if isExpanded {
                detailView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.windowBackgroundColor))
    }
    
    private var detailView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            
            HStack(spacing: 40) {
                // 타입 정보
                VStack(alignment: .leading, spacing: 8) {
                    Text("타입 구성")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.semibold)
                    
                    detailMetric(label: "Classes", value: analysis.classCount)
                    detailMetric(label: "Structs", value: analysis.structCount)
                    detailMetric(label: "Enums", value: analysis.enumCount)
                    detailMetric(label: "Protocols", value: analysis.protocolCount)
                }
                
                // 코드 정보
                VStack(alignment: .leading, spacing: 8) {
                    Text("코드 구성")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.semibold)
                    
                    detailMetric(label: "Properties", value: analysis.propertyCount)
                    detailMetric(label: "Functions", value: analysis.functionCount)
                    detailMetric(label: "순환 복잡도", value: analysis.cyclomaticComplexity)
                }
                
                Spacer()
                
                // 복잡도 게이지
                VStack(spacing: 8) {
                    Text("복잡도 분석")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.semibold)
                    
                    ZStack {
                        Circle()
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 8)
                            .frame(width: 100, height: 100)
                        
                        Circle()
                            .trim(from: 0, to: min(analysis.complexityScore / 500, 1.0))
                            .stroke(complexityColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 100, height: 100)
                            .rotationEffect(.degrees(-90))
                        
                        VStack(spacing: 2) {
                            Text(String(format: "%.0f", analysis.complexityScore))
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("점수")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .background(Color(.textBackgroundColor))
    }
    
    private func metricBadge(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(width: 50)
    }
    
    private func detailMetric(label: String, value: Int) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text("\(value)")
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
    
    private var complexityColor: Color {
        switch analysis.complexityLevel {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .veryHigh: return .red
        }
    }
}

#Preview {
    ContentView()
}
