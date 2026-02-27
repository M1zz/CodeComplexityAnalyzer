import SwiftUI
import Charts

struct TodoView: View {
    let items: [TodoItem]

    @State private var selectedKind: TodoItem.Kind? = nil
    @State private var searchText = ""

    private var filtered: [TodoItem] {
        items.filter {
            (selectedKind == nil || $0.kind == selectedKind) &&
            (searchText.isEmpty
                || $0.fileName.localizedCaseInsensitiveContains(searchText)
                || $0.content.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        if items.isEmpty {
            emptyView
        } else {
            HSplitView {
                listPanel.frame(minWidth: 420)
                dashboardPanel.frame(minWidth: 260, maxWidth: 380)
            }
        }
    }

    // MARK: - Empty

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 60)).foregroundColor(.green)
            Text("TODO / FIXME 없음").font(.title2).fontWeight(.semibold)
            Text("소스 코드에서 미완료 주석이 발견되지 않았습니다.")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List Panel

    private var listPanel: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(filtered) { item in TodoRow(item: item) }
                }
            }
        }
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("검색...", text: $searchText).textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8).background(Color(.textBackgroundColor)).cornerRadius(8)

            HStack(spacing: 8) {
                Menu {
                    Button("전체") { selectedKind = nil }
                    Divider()
                    ForEach(TodoItem.Kind.allCases, id: \.self) { k in
                        Button(k.rawValue) { selectedKind = k }
                    }
                } label: {
                    Label(selectedKind?.rawValue ?? "유형 전체",
                          systemImage: selectedKind?.icon ?? "line.3.horizontal.decrease.circle")
                        .font(.caption)
                }.menuStyle(.borderlessButton).fixedSize()

                Spacer()
                Text("\(filtered.count)개").font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(10).background(Color(.windowBackgroundColor))
    }

    // MARK: - Dashboard Panel

    private var dashboardPanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                kindCards
                kindChart
                topFilesChart
            }
            .padding()
        }
        .background(Color(.controlBackgroundColor))
    }

    private var kindCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach([TodoItem.Kind.fixme, .warning, .hack, .todo], id: \.self) { k in
                let cnt = items.filter { $0.kind == k }.count
                VStack(spacing: 4) {
                    Image(systemName: k.icon).font(.title3).foregroundColor(kindColor(k))
                    Text("\(cnt)").font(.title2).fontWeight(.bold).foregroundColor(kindColor(k))
                    Text(k.rawValue).font(.caption2).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(10)
                .background(kindColor(k).opacity(0.1)).cornerRadius(8)
            }
        }
    }

    private var kindChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("유형별 분포").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            let data = TodoItem.Kind.allCases.compactMap { k -> (kind: String, count: Int)? in
                let cnt = items.filter { $0.kind == k }.count
                return cnt > 0 ? (k.rawValue, cnt) : nil
            }
            Chart(data, id: \.kind) { item in
                BarMark(x: .value("수", item.count), y: .value("유형", item.kind))
                    .foregroundStyle(Color.blue.gradient)
                    .annotation(position: .trailing) {
                        Text("\(item.count)").font(.caption2).foregroundColor(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(data.count * 36 + 10))
        }
        .padding().background(Color(.windowBackgroundColor)).cornerRadius(10)
    }

    private var topFilesChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("파일별 TODO 수 (Top 5)").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
            let top = Dictionary(grouping: items, by: \.fileName)
                .map { (name: $0.key, count: $0.value.count) }
                .sorted { $0.count > $1.count }
                .prefix(5)
            Chart(top, id: \.name) { item in
                BarMark(x: .value("수", item.count), y: .value("파일", item.name))
                    .foregroundStyle(Color.orange.gradient)
                    .annotation(position: .trailing) {
                        Text("\(item.count)").font(.caption2).foregroundColor(.secondary)
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: CGFloat(min(top.count, 5) * 36 + 10))
        }
        .padding().background(Color(.windowBackgroundColor)).cornerRadius(10)
    }

    private func kindColor(_ k: TodoItem.Kind) -> Color {
        switch k {
        case .warning, .fixme: return .red
        case .hack:            return .orange
        case .todo:            return .blue
        case .mark:            return .secondary
        }
    }
}

// MARK: - Todo Row

struct TodoRow: View {
    let item: TodoItem

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(kindColor).frame(width: 3)

            HStack(spacing: 10) {
                Image(systemName: item.kind.icon)
                    .font(.body).foregroundColor(kindColor).frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        Text(item.fileName)
                            .font(.system(.caption, design: .monospaced)).fontWeight(.medium)
                        Text(":\(item.lineNumber)")
                            .font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary)
                    }
                    Text(item.content).font(.caption).foregroundColor(.secondary).lineLimit(2)
                }

                Spacer()

                Text(item.kind.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(kindColor.opacity(0.15))
                    .foregroundColor(kindColor)
                    .cornerRadius(4)
            }
            .padding(.vertical, 8).padding(.trailing, 12)
            .background(Color(.controlBackgroundColor))
        }
        .background(Color(.windowBackgroundColor))
    }

    private var kindColor: Color {
        switch item.kind {
        case .warning, .fixme: return .red
        case .hack:            return .orange
        case .todo:            return .blue
        case .mark:            return .secondary
        }
    }
}
