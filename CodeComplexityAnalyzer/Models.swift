import Foundation

struct FileAnalysis: Identifiable {
    let id = UUID()
    let fileName: String
    let filePath: String
    let lineCount: Int
    let functionCount: Int
    let classCount: Int
    let structCount: Int
    let enumCount: Int
    let protocolCount: Int
    let propertyCount: Int
    let cyclomaticComplexity: Int
    
    var complexityScore: Double {
        // 복잡도 점수 계산 (가중치 적용)
        let lineScore = Double(lineCount) * 0.1
        let functionScore = Double(functionCount) * 2.0
        let typeScore = Double(classCount + structCount + enumCount) * 3.0
        let complexityScore = Double(cyclomaticComplexity) * 1.5
        
        return lineScore + functionScore + typeScore + complexityScore
    }
    
    var complexityLevel: ComplexityLevel {
        switch complexityScore {
        case 0..<50: return .low
        case 50..<150: return .medium
        case 150..<300: return .high
        default: return .veryHigh
        }
    }
}

enum ComplexityLevel: String, CaseIterable {
    case low = "낮음"
    case medium = "보통"
    case high = "높음"
    case veryHigh = "매우 높음"
    
    var color: String {
        switch self {
        case .low: return "green"
        case .medium: return "yellow"
        case .high: return "orange"
        case .veryHigh: return "red"
        }
    }
}

struct ProjectSummary {
    let totalFiles: Int
    let totalLines: Int
    let totalFunctions: Int
    let averageComplexity: Double
    let mostComplexFile: FileAnalysis?
    let largestFile: FileAnalysis?
}

// MARK: - Health Score

enum HealthGrade: String {
    case a = "A", b = "B", c = "C", d = "D", f = "F"

    var color: String {
        switch self {
        case .a: return "green"
        case .b: return "blue"
        case .c: return "yellow"
        case .d: return "orange"
        case .f: return "red"
        }
    }
}

struct HealthScore {
    let overall: Double
    let complexityComponent: Double
    let dependencyComponent: Double
    let memoryComponent: Double
    let qualityComponent: Double
    let architectureComponent: Double

    var grade: HealthGrade {
        if overall >= 90 { return .a }
        else if overall >= 75 { return .b }
        else if overall >= 60 { return .c }
        else if overall >= 45 { return .d }
        else { return .f }
    }

    var statusLabel: String {
        switch grade {
        case .a, .b: return "양호"
        case .c: return "주의 필요"
        case .d, .f: return "즉시 개선 필요"
        }
    }
}

// MARK: - Action Item

enum ActionCategory: String, CaseIterable {
    case complexity  = "복잡도"
    case dependency  = "의존성"
    case memory      = "메모리"
    case quality     = "품질"
    case architecture = "아키텍처"
}

enum ActionSeverity: Int, Comparable {
    case critical = 0
    case warning  = 1
    case info     = 2

    static func < (lhs: ActionSeverity, rhs: ActionSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .critical: return "긴급"
        case .warning:  return "경고"
        case .info:     return "정보"
        }
    }

    var colorName: String {
        switch self {
        case .critical: return "red"
        case .warning:  return "orange"
        case .info:     return "blue"
        }
    }
}

struct ActionItem: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let fileName: String
    let filePath: String
    let category: ActionCategory
    let severity: ActionSeverity
    let impactScore: Double
}

// MARK: - Project Snapshot

struct ProjectSnapshot: Codable, Identifiable {
    let id: UUID
    let date: Date
    let projectPath: String
    let healthScore: Double
    let grade: String
    let complexityScore: Double
    let dependencyScore: Double
    let memoryScore: Double
    let qualityScore: Double
    let architectureScore: Double   // 신규 (구버전은 70.0 기본값)
    let totalFiles: Int
    let totalFunctions: Int
    let averageComplexity: Double
    let memoryIssueCount: Int
    let qualityOverallScore: Double
    var note: String?               // 사용자 메모 (선택)

    init(id: UUID, date: Date, projectPath: String, healthScore: Double, grade: String,
         complexityScore: Double, dependencyScore: Double, memoryScore: Double,
         qualityScore: Double, architectureScore: Double, totalFiles: Int,
         totalFunctions: Int, averageComplexity: Double, memoryIssueCount: Int,
         qualityOverallScore: Double, note: String? = nil) {
        self.id = id; self.date = date; self.projectPath = projectPath
        self.healthScore = healthScore; self.grade = grade
        self.complexityScore = complexityScore; self.dependencyScore = dependencyScore
        self.memoryScore = memoryScore; self.qualityScore = qualityScore
        self.architectureScore = architectureScore
        self.totalFiles = totalFiles; self.totalFunctions = totalFunctions
        self.averageComplexity = averageComplexity; self.memoryIssueCount = memoryIssueCount
        self.qualityOverallScore = qualityOverallScore; self.note = note
    }

    // 구버전 데이터 호환을 위한 커스텀 디코더
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                = try c.decode(UUID.self,   forKey: .id)
        date              = try c.decode(Date.self,   forKey: .date)
        projectPath       = try c.decode(String.self, forKey: .projectPath)
        healthScore       = try c.decode(Double.self, forKey: .healthScore)
        grade             = try c.decode(String.self, forKey: .grade)
        complexityScore   = try c.decode(Double.self, forKey: .complexityScore)
        dependencyScore   = try c.decode(Double.self, forKey: .dependencyScore)
        memoryScore       = try c.decode(Double.self, forKey: .memoryScore)
        qualityScore      = try c.decode(Double.self, forKey: .qualityScore)
        architectureScore = (try? c.decodeIfPresent(Double.self, forKey: .architectureScore)) ?? 70.0
        totalFiles        = try c.decode(Int.self,    forKey: .totalFiles)
        totalFunctions    = try c.decode(Int.self,    forKey: .totalFunctions)
        averageComplexity = try c.decode(Double.self, forKey: .averageComplexity)
        memoryIssueCount  = try c.decode(Int.self,    forKey: .memoryIssueCount)
        qualityOverallScore = try c.decode(Double.self, forKey: .qualityOverallScore)
        note              = try? c.decodeIfPresent(String.self, forKey: .note)
    }
}

// MARK: - Metric Explanation

struct MetricExplanation {
    let plainTerm: String
    let explanation: String

    static let catalog: [String: MetricExplanation] = [
        "cyclomaticComplexity": MetricExplanation(
            plainTerm: "순환 복잡도",
            explanation: "코드 안의 분기(if/for/switch)가 얼마나 많은지 나타냅니다. 숫자가 클수록 테스트하기 어렵고 버그가 숨기 쉽습니다. 10 이하가 이상적입니다."
        ),
        "scc": MetricExplanation(
            plainTerm: "소스코드 복잡도 점수",
            explanation: "파일의 라인 수, 함수 수, 순환 복잡도를 종합한 점수입니다. 높을수록 파일이 복잡하고 유지보수가 어렵습니다."
        ),
        "commentRatio": MetricExplanation(
            plainTerm: "주석 비율",
            explanation: "전체 코드 중 주석이 차지하는 비율입니다. 5% 이상이 권장되며, 주석이 적으면 코드를 나중에 이해하기 어렵습니다."
        ),
        "avgFunctionLen": MetricExplanation(
            plainTerm: "평균 함수 길이",
            explanation: "함수 하나가 평균 몇 줄인지 나타냅니다. 함수가 짧을수록(20줄 이하) 이해하기 쉽고 테스트하기 좋습니다."
        ),
        "healthScore": MetricExplanation(
            plainTerm: "프로젝트 건강 점수",
            explanation: "복잡도, 의존성, 메모리 안전성, 코드 품질을 종합한 점수입니다. 100점에 가까울수록 잘 관리된 코드입니다."
        ),
        "memoryLeak": MetricExplanation(
            plainTerm: "메모리 누수 위험",
            explanation: "앱이 메모리를 해제하지 못하는 패턴을 감지합니다. 방치하면 앱이 느려지거나 강제 종료될 수 있습니다."
        ),
        "archHealth": MetricExplanation(
            plainTerm: "아키텍처 건강도",
            explanation: "코드가 얼마나 잘 계층별로 분리되어 있는지 나타냅니다. 점수가 높을수록 기능 추가와 버그 수정이 쉽습니다."
        ),
        "layerViolation": MetricExplanation(
            plainTerm: "레이어 위반",
            explanation: "화면을 담당하는 코드가 데이터를 직접 다루거나, 데이터 코드가 화면에 의존하는 경우입니다. 이러면 코드가 엉켜 수정하기 어려워집니다."
        )
    ]
}
