import SwiftUI
import Charts

struct FunctionView: View {
    let functions: [FunctionInfo]

    @State private var sortBy:        SortBy          = .cc
    @State private var searchText                      = ""
    @State private var selectedLevel: ComplexityLevel? = nil

    enum SortBy: String, CaseIterable {
        case cc     = "복잡도"
        case length = "길이"
        case params = "파라미터"
        case name   = "이름"
    }

    private var filtered: [FunctionInfo] {
        var r = functions
        if let lv = selectedLevel { r = r.filter { $0.ccLevel == lv } }
        if !searchText.isEmpty {
            r = r.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.fileName.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortBy {
        case .cc:     r.sort { $0.cc > $1.cc }
        case .length: r.sort { $0.lineCount > $1.lineCount }
        case .params: r.sort { $0.paramCount > $1.paramCount }
        case .name:   r.sort { $0.name < $1.name }
        }
        return r
    }

    var body: some View {
        if functions.isEmpty {
            emptyView
        } else {
            HSplitView {
                listPanel.frame(minWidth: 440)
                statsPanel.frame(minWidth: 280, maxWidth: 380)
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "function").font(.system(size: 60)).foregroundColor(.secondary)
            Text("분석된 함수 없음").font(.title2).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List Panel

    private var listPanel: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered) { fn in FunctionRow(fn: fn) }
                }
            }
        }
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("함수 / 파일 검색...", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8).background(Color(.textBackgroundColor)).cornerRadius(8)

            HStack {
                Menu {
                    Button("전체") { selectedLevel = nil }
                    Divider()
                    ForEach(ComplexityLevel.allCases, id: \.self) { lv in
                        Button(lv.rawValue) { selectedLevel = lv }
                    }
                } label: {
                    Label(selectedLevel?.rawValue ?? "복잡도 전체",
                          systemImage: "speedometer").font(.body)
                }.menuStyle(.borderlessButton).fixedSize()

                Spacer()

                Picker("정렬", selection: $sortBy) {
                    ForEach(SortBy.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 280)

                Text("\(filtered.count)개").font(.body).foregroundColor(.secondary)
            }
        }
        .padding(10).background(Color(.windowBackgroundColor))
    }

    // MARK: - Stats Panel

    private var statsPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCards
                complexityDistChart
                topLengthChart
            }
            .padding()
        }
        .background(Color(.controlBackgroundColor))
    }

    private var summaryCards: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                statCard("총 함수", "\(functions.count)", .blue)
                statCard("평균 길이", String(format: "%.1f줄", avgLen), .green)
            }
            HStack(spacing: 10) {
                statCard("평균 CC", String(format: "%.1f", avgCC), .orange)
                statCard("최대 파라미터", "\(maxParams)", .purple)
            }
        }
    }

    private func statCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(color)
            Text(title).font(.body).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity).padding(10)
        .background(color.opacity(0.1)).cornerRadius(8)
    }

    private var avgLen: Double {
        functions.isEmpty ? 0 : Double(functions.map(\.lineCount).reduce(0, +)) / Double(functions.count)
    }
    private var avgCC: Double {
        functions.isEmpty ? 0 : Double(functions.map(\.cc).reduce(0, +)) / Double(functions.count)
    }
    private var maxParams: Int { functions.map(\.paramCount).max() ?? 0 }

    private var complexityDistChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("복잡도 분포").font(.body).fontWeight(.semibold).foregroundColor(.secondary)
            let data = ComplexityLevel.allCases.compactMap { lv -> (label: String, count: Int)? in
                let cnt = functions.filter { $0.ccLevel == lv }.count
                return cnt > 0 ? (lv.rawValue, cnt) : nil
            }
            Chart(data, id: \.label) { item in
                BarMark(x: .value("수", item.count), y: .value("등급", item.label))
                    .foregroundStyle(Color.purple.gradient)
                    .annotation(position: .trailing) {
                        Text("\(item.count)").font(.body).foregroundColor(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(data.count * 36 + 10))
        }
        .padding().background(Color(.windowBackgroundColor)).cornerRadius(10)
    }

    private var topLengthChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("가장 긴 함수 Top 5").font(.body).fontWeight(.semibold).foregroundColor(.secondary)
            let top = Array(functions.sorted { $0.lineCount > $1.lineCount }.prefix(5))
            Chart(top) { fn in
                BarMark(x: .value("줄", fn.lineCount), y: .value("함수", fn.name))
                    .foregroundStyle(Color.red.gradient)
                    .annotation(position: .trailing) {
                        Text("\(fn.lineCount)").font(.body).foregroundColor(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(top.count * 36 + 10))
        }
        .padding().background(Color(.windowBackgroundColor)).cornerRadius(10)
    }
}

// MARK: - Function Row

struct FunctionRow: View {
    let fn: FunctionInfo
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(ccColor).frame(width: 10, height: 10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(fn.name)
                            .font(.system(.body, design: .monospaced)).fontWeight(.medium)
                        Text("\(fn.fileName):\(fn.startLine)")
                            .font(.body).foregroundColor(.secondary)
                    }

                    Spacer()
                    badge("\(fn.lineCount)", "lines",   .blue)
                    badge("\(fn.paramCount)", "params", .purple)
                    badge("CC \(fn.cc)", fn.ccLevel.rawValue, ccColor)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.body).foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.controlBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    Text(fn.signature)
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.textBackgroundColor))
                        .cornerRadius(6)
                    Text(fn.filePath)
                        .font(.body).foregroundColor(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
                .background(Color(.textBackgroundColor))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private func badge(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.callout).fontWeight(.semibold).foregroundColor(color)
            Text(label).font(.body).foregroundColor(.secondary)
        }.frame(width: 56)
    }

    private var ccColor: Color {
        switch fn.ccLevel {
        case .low:      return .green
        case .medium:   return .yellow
        case .high:     return .orange
        case .veryHigh: return .red
        }
    }
}
