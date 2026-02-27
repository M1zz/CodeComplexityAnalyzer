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
