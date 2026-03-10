import SwiftUI

struct HomeView: View {
    let healthScore: HealthScore?
    let healthTrend: Double?
    let actionItems: [ActionItem]
    let selectedPath: String?
    let onNavigate: (ViewMode) -> Void
    var onSelectFolder: (() -> Void)? = nil

    private var projectName: String {
        guard let path = selectedPath else { return "프로젝트 없음" }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let health = healthScore {
                    analysisResultView(health: health)
                } else {
                    emptyStateView
                }
            }
            .padding()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("프로젝트를 선택해주세요")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Xcode 프로젝트 폴더를 선택하면\n건강 점수와 개선 방향을 알려드립니다")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
            }

            if let onSelect = onSelectFolder {
                Button(action: onSelect) {
                    Label("프로젝트 폴더 선택", systemImage: "folder")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    // MARK: - Analysis Result

    private func analysisResultView(health: HealthScore) -> some View {
        VStack(spacing: 20) {
            // 헤더: 프로젝트명 + 마지막 분석 날짜
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(projectName)
                        .font(.title3)
                        .fontWeight(.bold)
                }
                Spacer()
            }

            // 건강 점수 카드
            healthScoreCard(health: health)

            // 개선 잠재량 카드
            if !actionItems.isEmpty {
                improvementPotentialCard(health: health)
            }

            // 3개 액션 카드
            HStack(spacing: 12) {
                actionCard(
                    icon: "exclamationmark.triangle.fill",
                    title: "지금 고쳐야 할 것",
                    subtitle: actionItems.isEmpty ? "이슈 없음" : "\(actionItems.filter { $0.severity == .critical }.count)개 긴급 · \(actionItems.filter { $0.severity == .warning }.count)개 경고",
                    color: .orange,
                    destination: .actions
                )
                actionCard(
                    icon: "list.bullet",
                    title: "전체 현황",
                    subtitle: "파일별 복잡도 목록",
                    color: .blue,
                    destination: .list
                )
                actionCard(
                    icon: "network",
                    title: "의존성",
                    subtitle: "관계도 · 의존성 분석",
                    color: .purple,
                    destination: .dependency
                )
            }
        }
    }

    // MARK: - Improvement Potential Card

    private func improvementPotentialCard(health: HealthScore) -> some View {
        let totalPotential = actionItems.map(\.impactScore).reduce(0, +)
        let projected = min(100.0, health.overall + totalPotential)
        let criticalCount = actionItems.filter { $0.severity == .critical }.count
        return HStack(spacing: 0) {
            // 현재 → 예상
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("현재").font(.body).foregroundColor(.secondary)
                    Text(String(format: "%.0f점", health.overall))
                        .font(.title3).fontWeight(.bold)
                }
                Image(systemName: "arrow.right").foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("모두 해결 시").font(.body).foregroundColor(.secondary)
                    Text(String(format: "%.0f점", projected))
                        .font(.title3).fontWeight(.bold).foregroundColor(.green)
                }
                Text(String(format: "(+%.1f점)", totalPotential))
                    .font(.body).fontWeight(.semibold).foregroundColor(.green)
            }
            .padding()

            Divider().frame(height: 40)

            // 할 일 요약
            VStack(alignment: .leading, spacing: 2) {
                Text("할 일 \(actionItems.count)개")
                    .font(.body).fontWeight(.semibold)
                Text(criticalCount > 0 ? "긴급 \(criticalCount)개 포함" : "긴급 항목 없음")
                    .font(.body)
                    .foregroundColor(criticalCount > 0 ? .red : .secondary)
            }
            .padding()

            Spacer()

            Button { onNavigate(.actions) } label: {
                Label("할 일 보기", systemImage: "chevron.right")
                    .font(.body).fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .padding(.trailing)
        }
        .background(Color.green.opacity(0.07))
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Health Score Card

    private func healthScoreCard(health: HealthScore) -> some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 20) {
                // 등급 + 점수
                VStack(spacing: 4) {
                    Text(health.grade.rawValue)
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundColor(gradeColor(health.grade))

                    HStack(spacing: 4) {
                        Text(String(format: "%.0f점", health.overall))
                            .font(.title3)
                            .fontWeight(.semibold)
                        if let trend = healthTrend {
                            trendBadge(trend: trend)
                        }
                    }
                    Text(health.statusLabel)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(gradeColor(health.grade).opacity(0.15))
                        .cornerRadius(8)
                }

                Divider()
                    .frame(height: 100)

                // 5개 컴포넌트 바 (높을수록 좋음: 초록 ≥75, 노랑 50–74, 빨강 <50)
                VStack(alignment: .leading, spacing: 8) {
                    componentBar(label: "복잡도", value: health.complexityComponent)
                    componentBar(label: "의존성", value: health.dependencyComponent)
                    componentBar(label: "메모리", value: health.memoryComponent)
                    componentBar(label: "품질",   value: health.qualityComponent)
                    componentBar(label: "아키텍처", value: health.architectureComponent)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func componentBar(label: String, value: Double) -> some View {
        let barColor = healthColor(value)
        return HStack(spacing: 8) {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.opacity(0.85))
                        .frame(width: geo.size.width * min(value / 100.0, 1.0))
                }
            }
            .frame(height: 6)
            Text(String(format: "%.0f", value))
                .font(.body)
                .fontWeight(.semibold)
                .foregroundColor(barColor)
                .frame(width: 28, alignment: .trailing)
        }
    }

    /// 높을수록 좋음: 75이상 초록, 50–74 노랑, 50미만 빨강
    private func healthColor(_ value: Double) -> Color {
        if value >= 75 { return .green }
        if value >= 50 { return Color(red: 0.9, green: 0.6, blue: 0.0) } // amber
        return .red
    }

    private func trendBadge(trend: Double) -> some View {
        let isUp = trend >= 0
        return HStack(spacing: 2) {
            Image(systemName: isUp ? "arrow.up" : "arrow.down")
            Text(String(format: "%+.0f", trend))
        }
        .font(.body)
        .fontWeight(.semibold)
        .foregroundColor(isUp ? .green : .red)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background((isUp ? Color.green : Color.red).opacity(0.12))
        .cornerRadius(6)
    }

    private func gradeColor(_ grade: HealthGrade) -> Color {
        switch grade {
        case .a: return .green
        case .b: return .blue
        case .c: return .yellow
        case .d: return .orange
        case .f: return .red
        }
    }

    // MARK: - Action Card

    private func actionCard(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        destination: ViewMode
    ) -> some View {
        Button { onNavigate(destination) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.callout)
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
