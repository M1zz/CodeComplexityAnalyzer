import SwiftUI
import Charts

struct GitHistoryView: View {
    let report: GitHistoryReport

    @State private var searchText        = ""
    @State private var selectedHotspot: GitFileChange.Hotspot? = nil

    private var filtered: [GitFileChange] {
        report.fileChanges.filter {
            (selectedHotspot == nil || $0.hotspot == selectedHotspot) &&
            (searchText.isEmpty || $0.fileName.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        if !report.isGitRepo {
            notGitView
        } else if report.fileChanges.isEmpty {
            emptyView
        } else {
            VStack(spacing: 0) {
                summaryBanner
                Divider()
                HSplitView {
                    listPanel.frame(minWidth: 420)
                    chartsPanel.frame(minWidth: 260, maxWidth: 380)
                }
            }
        }
    }

    // MARK: - States

    private var notGitView: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.xmark")
                .font(.system(size: 60)).foregroundColor(.secondary)
            Text("Git 저장소 아님").font(.title2).fontWeight(.semibold)
            Text("선택한 폴더에 .git 디렉토리가 없습니다.\nGit으로 관리되는 프로젝트를 선택하세요.")
                .foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60)).foregroundColor(.secondary)
            Text("변경 이력 없음").font(.title2).fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Banner

    private var summaryBanner: some View {
        HStack(spacing: 24) {
            metric("총 커밋",   "\(report.totalCommits)회",                          .blue)
            metric("추적 파일", "\(report.fileChanges.count)개",                     .green)
            metric("핫스팟",   "\(report.fileChanges.filter { $0.hotspot == .veryHot }.count)개", .red)
            metric("기여자",   "\(report.topAuthors.count)명",                       .purple)

            if !report.topAuthors.isEmpty {
                Divider().frame(height: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("주요 기여자").font(.body).foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        ForEach(report.topAuthors.prefix(3), id: \.self) { a in
                            Text(a)
                                .font(.body)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1)).cornerRadius(4)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(.controlBackgroundColor))
    }

    private func metric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.body).foregroundColor(.secondary)
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
                    ForEach(filtered) { change in GitFileRow(change: change) }
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

            Menu {
                Button("전체") { selectedHotspot = nil }
                Divider()
                ForEach(GitFileChange.Hotspot.allCases, id: \.rawValue) { h in
                    Button(h.rawValue) { selectedHotspot = h }
                }
            } label: {
                Label(selectedHotspot?.rawValue ?? "핫스팟 전체",
                      systemImage: selectedHotspot?.icon ?? "flame").font(.body)
            }.menuStyle(.borderlessButton).fixedSize()

            Spacer()
            Text("\(filtered.count)개").font(.body).foregroundColor(.secondary)
        }
        .padding(10).background(Color(.windowBackgroundColor))
    }

    // MARK: - Charts Panel

    private var chartsPanel: some View {
        ScrollView {
            VStack(spacing: 16) { hotspotCards; topCommitChart }
                .padding()
        }
        .background(Color(.controlBackgroundColor))
    }

    private var hotspotCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(GitFileChange.Hotspot.allCases, id: \.rawValue) { h in
                let cnt = report.fileChanges.filter { $0.hotspot == h }.count
                VStack(spacing: 4) {
                    Image(systemName: h.icon).font(.title3).foregroundColor(hotspotColor(h))
                    Text("\(cnt)").font(.title2).fontWeight(.bold).foregroundColor(hotspotColor(h))
                    Text(h.rawValue).font(.body).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(10)
                .background(hotspotColor(h).opacity(0.1)).cornerRadius(8)
            }
        }
    }

    private var topCommitChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("변경 빈도 Top 10").font(.body).fontWeight(.semibold).foregroundColor(.secondary)
            let top = Array(report.fileChanges.prefix(10))
            Chart(top) { c in
                BarMark(x: .value("커밋", c.commitCount), y: .value("파일", c.fileName))
                    .foregroundStyle(Color.red.gradient)
                    .annotation(position: .trailing) {
                        Text("\(c.commitCount)").font(.body).foregroundColor(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(top.count * 32 + 10))
        }
        .padding().background(Color(.windowBackgroundColor)).cornerRadius(10)
    }

    private func hotspotColor(_ h: GitFileChange.Hotspot) -> Color {
        switch h {
        case .cold:    return .blue
        case .warm:    return .green
        case .hot:     return .orange
        case .veryHot: return .red
        }
    }
}

// MARK: - Git File Row

struct GitFileRow: View {
    let change: GitFileChange
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: change.hotspot.icon)
                        .font(.body).foregroundColor(hotspotColor).frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.fileName)
                            .font(.system(.body, design: .monospaced)).fontWeight(.medium)
                        if let date = change.lastModified {
                            Text("최근 수정: \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.body).foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("\(change.commitCount)")
                            .font(.title3).fontWeight(.bold).foregroundColor(hotspotColor)
                        Text("커밋").font(.body).foregroundColor(.secondary)
                    }.frame(width: 50)

                    Text(change.hotspot.rawValue)
                        .font(.body)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(hotspotColor.opacity(0.15))
                        .foregroundColor(hotspotColor)
                        .cornerRadius(4)

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
                    if !change.authors.isEmpty {
                        Label("기여자: " + change.authors.joined(separator: ", "),
                              systemImage: "person.2")
                            .font(.body).foregroundColor(.secondary)
                    }
                    Text(change.filePath)
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

    private var hotspotColor: Color {
        switch change.hotspot {
        case .cold:    return .blue
        case .warm:    return .green
        case .hot:     return .orange
        case .veryHot: return .red
        }
    }
}
