import SwiftUI

struct PerformanceView: View {

    let report: PerformanceReport?
    let healthScore: HealthScore?

    @State private var selectedCategory: PerformanceIssue.Category? = nil
    @State private var expandedID: UUID? = nil

    // MARK: - Computed

    private var issues: [PerformanceIssue] {
        guard let report else { return [] }
        if let cat = selectedCategory {
            return report.issues.filter { $0.category == cat }
        }
        return report.issues
    }

    private var potentialImprovement: Double {
        guard let report else { return 0 }
        return min(20.0, Double(report.issues.filter { $0.severity == .high }.count) * 3.0
                       + Double(report.issues.filter { $0.severity == .medium }.count) * 1.0)
    }

    // MARK: - Body

    var body: some View {
        if let report {
            VStack(spacing: 0) {
                scoreBanner(report: report)
                Divider()
                categoryFilter(report: report)
                Divider()
                issueList
            }
        } else {
            ContentUnavailableView(
                "최적화 분석 없음",
                systemImage: "bolt.slash",
                description: Text("프로젝트를 분석하면 성능 개선 포인트를 찾아드립니다.")
            )
        }
    }

    // MARK: - Score Banner

    private func scoreBanner(report: PerformanceReport) -> some View {
        HStack(spacing: 20) {
            // 점수
            VStack(alignment: .leading, spacing: 2) {
                Text("성능 최적화 점수")
                    .font(.body)
                    .foregroundColor(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(String(format: "%.0f", report.score))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(scoreColor(report.score))
                    Text("/ 100")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }

            Divider().frame(height: 44)

            // 카테고리별 이슈 수
            ForEach(PerformanceIssue.Category.allCases, id: \.self) { cat in
                let count = report.byCategory[cat]?.count ?? 0
                VStack(spacing: 3) {
                    Text("\(count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(count > 0 ? categoryColor(cat) : .secondary)
                    Text(cat.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(minWidth: 52)
            }

            Divider().frame(height: 44)

            // 설명
            VStack(alignment: .leading, spacing: 2) {
                Text("총 \(report.issues.count)개 이슈")
                    .font(.body)
                    .fontWeight(.semibold)
                if potentialImprovement > 0 {
                    Text(String(format: "해결 시 예상 개선 +%.0f점", potentialImprovement))
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("최적화 이슈 없음")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            // 가이드 텍스트
            VStack(alignment: .trailing, spacing: 2) {
                Text("높을수록 최적화된 코드")
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(spacing: 8) {
                    Label("75↑ 양호", systemImage: "circle.fill").foregroundColor(.green)
                    Label("50↑ 주의", systemImage: "circle.fill").foregroundColor(.orange)
                    Label("50↓ 위험", systemImage: "circle.fill").foregroundColor(.red)
                }
                .font(.caption2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(scoreColor(report.score).opacity(0.07))
    }

    // MARK: - Category Filter

    private func categoryFilter(report: PerformanceReport) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "전체", count: report.issues.count, selected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(PerformanceIssue.Category.allCases, id: \.self) { cat in
                    let cnt = report.byCategory[cat]?.count ?? 0
                    filterChip(label: cat.rawValue, count: cnt, selected: selectedCategory == cat,
                               color: categoryColor(cat)) {
                        selectedCategory = selectedCategory == cat ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func filterChip(
        label: String, count: Int, selected: Bool,
        color: Color = .accentColor, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(label)
                    .fontWeight(selected ? .semibold : .regular)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(selected ? Color.white.opacity(0.3) : color.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(selected ? color : Color(.controlBackgroundColor))
            .foregroundColor(selected ? .white : .primary)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Issue List

    private var issueList: some View {
        Group {
            if issues.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)
                    Text("이 카테고리의 이슈가 없습니다")
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("최적화 관점에서 문제가 발견되지 않았습니다.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(issues) { issue in
                            issueRow(issue)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func issueRow(_ issue: PerformanceIssue) -> some View {
        let isExpanded = expandedID == issue.id
        return VStack(alignment: .leading, spacing: 0) {
            // 헤더
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedID = isExpanded ? nil : issue.id
                }
            } label: {
                HStack(spacing: 10) {
                    // 심각도 색상 인디케이터
                    RoundedRectangle(cornerRadius: 2)
                        .fill(severityColor(issue.severity))
                        .frame(width: 4, height: 40)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            // 심각도 뱃지
                            Text(issue.severity.label)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(severityColor(issue.severity))
                                .cornerRadius(4)
                            // 카테고리
                            Text(issue.category.rawValue)
                                .font(.caption)
                                .foregroundColor(categoryColor(issue.category))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(categoryColor(issue.category).opacity(0.12))
                                .cornerRadius(4)
                        }
                        Text(issue.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(issue.fileName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Line \(issue.line)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // 상세 정보
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                    // 문제 설명
                    VStack(alignment: .leading, spacing: 4) {
                        Label("왜 문제인가?", systemImage: "info.circle")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        Text(issue.detail)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // 개선 방향
                    VStack(alignment: .leading, spacing: 4) {
                        Label("개선 방향", systemImage: "lightbulb")
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundColor(.orange)
                        Text(issue.suggestion)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Color Helpers

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return .green }
        if score >= 50 { return Color(red: 0.9, green: 0.6, blue: 0.0) }
        return .red
    }

    private func severityColor(_ sev: PerformanceIssue.Severity) -> Color {
        switch sev {
        case .high:   return .red
        case .medium: return .orange
        case .low:    return .blue
        }
    }

    private func categoryColor(_ cat: PerformanceIssue.Category) -> Color {
        switch cat {
        case .rendering:      return .purple
        case .concurrency:    return .red
        case .algorithm:      return .blue
        case .initialization: return .orange
        case .debug:          return Color(red: 0.4, green: 0.4, blue: 0.4)
        }
    }
}
