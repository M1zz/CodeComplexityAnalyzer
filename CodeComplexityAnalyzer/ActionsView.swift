import SwiftUI
import Charts

struct ActionsView: View {
    let items: [ActionItem]
    @State private var selectedCategory: ActionCategory? = nil

    private var filteredItems: [ActionItem] {
        guard let cat = selectedCategory else { return items }
        return items.filter { $0.category == cat }
    }

    private var categoryCounts: [(category: ActionCategory, count: Int, impact: Double)] {
        ActionCategory.allCases.map { cat in
            let catItems = items.filter { $0.category == cat }
            return (cat, catItems.count, catItems.map(\.impactScore).reduce(0, +))
        }.filter { $0.count > 0 }
    }

    var body: some View {
        if items.isEmpty {
            emptyStateView
        } else {
            HSplitView {
                // 왼쪽: 액션 리스트
                VStack(spacing: 0) {
                    categoryFilterBar
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredItems) { item in
                                ActionRow(item: item)
                            }
                        }
                    }
                }
                .frame(minWidth: 400)

                // 오른쪽: 카테고리별 영향도 차트
                impactChartPanel
                    .frame(minWidth: 260, maxWidth: 320)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("개선할 항목이 없습니다")
                .font(.title2)
                .fontWeight(.medium)
            Text("프로젝트 건강 상태가 양호합니다")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Filter Bar

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(label: "전체", category: nil)
                ForEach(ActionCategory.allCases, id: \.self) { cat in
                    let count = items.filter { $0.category == cat }.count
                    if count > 0 {
                        filterChip(label: "\(cat.rawValue) \(count)", category: cat)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.windowBackgroundColor))
    }

    private func filterChip(label: String, category: ActionCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button { selectedCategory = category } label: {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Impact Chart

    private var impactChartPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("카테고리별 영향도")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            if #available(macOS 13, *) {
                Chart(categoryCounts, id: \.category) { entry in
                    BarMark(
                        x: .value("영향도", entry.impact),
                        y: .value("카테고리", entry.category.rawValue)
                    )
                    .foregroundStyle(categoryColor(entry.category))
                    .annotation(position: .trailing) {
                        Text(String(format: "%.0f", entry.impact))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .chartXAxisLabel("예상 점수 향상")
                .padding()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(categoryCounts, id: \.category) { entry in
                    HStack {
                        Circle()
                            .fill(categoryColor(entry.category))
                            .frame(width: 8, height: 8)
                        Text(entry.category.rawValue)
                            .font(.caption)
                        Spacer()
                        Text("\(entry.count)개")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom)

            Spacer()
        }
        .background(Color(.controlBackgroundColor))
    }

    private func categoryColor(_ category: ActionCategory) -> Color {
        switch category {
        case .complexity:   return .orange
        case .dependency:   return .blue
        case .memory:       return .red
        case .quality:      return .green
        case .architecture: return .purple
        }
    }
}

// MARK: - ActionRow

struct ActionRow: View {
    let item: ActionItem
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 0) {
                    // 심각도 색상 바
                    severityIndicator
                        .frame(width: 4)

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.fileName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text(item.title)
                                .font(.callout)
                                .fontWeight(.medium)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            impactBadge
                            categoryBadge
                        }

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .background(Color(.controlBackgroundColor))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                detailView
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.windowBackgroundColor))
    }

    private var severityIndicator: some View {
        Rectangle()
            .fill(severityColor)
            .frame(maxHeight: .infinity)
    }

    private var impactBadge: some View {
        Text("+\(String(format: "%.0f", item.impactScore))점")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.green)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.12))
            .cornerRadius(6)
    }

    private var categoryBadge: some View {
        Text(item.category.rawValue)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(6)
    }

    private var detailView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text(item.detail)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
            ActionCopyPromptButton(item: item)
                .padding(.top, 4)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
        }
        .background(Color(.textBackgroundColor))
    }

    private var severityColor: Color {
        switch item.severity {
        case .critical: return .red
        case .warning:  return .orange
        case .info:     return .blue
        }
    }
}

// MARK: - ActionCopyPromptButton

fileprivate struct ActionCopyPromptButton: View {
    let item: ActionItem
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(makePrompt(), forType: .string)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { copied = false }
            }
        } label: {
            Label(
                copied ? "복사됨!" : "AI 수정 프롬프트 복사",
                systemImage: copied ? "checkmark.circle.fill" : "doc.on.clipboard"
            )
            .font(.caption).fontWeight(.semibold)
            .foregroundColor(copied ? .green : .accentColor)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private func makePrompt() -> String {
        """
        다음 Swift 프로젝트 문제를 수정해줘.

        파일: \(item.filePath)
        카테고리: \(item.category.rawValue)
        심각도: \(item.severity == .critical ? "긴급" : item.severity == .warning ? "경고" : "정보")

        문제:
        \(item.title)

        상세 설명:
        \(item.detail)
        """
    }
}
