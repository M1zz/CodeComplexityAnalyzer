import Foundation

// MARK: - Models

struct FileQuality: Identifiable {
    let id = UUID()
    let file:               FileAnalysis
    let score:              Double    // 0 – 100
    let commentRatio:       Double    // 0.0 – 1.0
    let avgFunctionLength:  Double
    let longFunctionCount:  Int       // lineCount > 40
    let complexFunctionCount: Int     // CC > 10
    let issues:             [String]
}

struct CodeQualityReport {
    let files:           [FileQuality]  // sorted worst-first
    let overallScore:    Double
    let avgCommentRatio: Double
    let avgFunctionLen:  Double
    let testFileCount:   Int
}

// MARK: - Analyzer

struct CodeQualityAnalyzer {

    func analyze(files: [FileAnalysis], functions: [FunctionInfo]) -> CodeQualityReport {
        let funcsByFile = Dictionary(grouping: functions, by: { $0.filePath })

        let qualities = files
            .map { analyzeFile($0, funcs: funcsByFile[$0.filePath] ?? []) }
            .sorted { $0.score < $1.score }

        let testFiles = files.filter {
            let n = $0.fileName.lowercased()
            return n.contains("test") || n.contains("spec")
        }.count

        let cnt = Double(qualities.count)
        return CodeQualityReport(
            files:           qualities,
            overallScore:    cnt > 0 ? qualities.map(\.score).reduce(0, +) / cnt : 0,
            avgCommentRatio: cnt > 0 ? qualities.map(\.commentRatio).reduce(0, +) / cnt : 0,
            avgFunctionLen:  cnt > 0 ? qualities.map(\.avgFunctionLength).reduce(0, +) / cnt : 0,
            testFileCount:   testFiles
        )
    }

    private func analyzeFile(_ file: FileAnalysis, funcs: [FunctionInfo]) -> FileQuality {
        let raw   = (try? String(contentsOfFile: file.filePath, encoding: .utf8)) ?? ""
        let lines = raw.components(separatedBy: "\n")

        // Comment ratio
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        let comments = lines.filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("//") || t.hasPrefix("/*") || t.hasPrefix("*")
        }.count
        let ratio = nonBlank > 0 ? Double(comments) / Double(nonBlank) : 0

        // Function metrics
        let longFuncs    = funcs.filter { $0.lineCount > 40 }.count
        let complexFuncs = funcs.filter { $0.cc > 10 }.count
        let avgLen       = funcs.isEmpty ? 0.0
            : Double(funcs.map(\.lineCount).reduce(0, +)) / Double(funcs.count)

        // Issues
        var issues = [String]()
        if ratio < 0.05 && file.lineCount > 50  { issues.append("주석 비율 \(Int(ratio * 100))% — 문서화 권장") }
        if longFuncs    > 0 { issues.append("40줄 초과 함수 \(longFuncs)개") }
        if complexFuncs > 0 { issues.append("순환복잡도 > 10 함수 \(complexFuncs)개") }
        if file.lineCount > 400 { issues.append("파일 크기 \(file.lineCount)줄 — 분리 권장") }

        // Score
        var score = 100.0
        score -= Double(longFuncs)    * 6.0
        score -= Double(complexFuncs) * 8.0
        if ratio < 0.05 && file.lineCount > 50 { score -= 10.0 }
        if      file.lineCount > 500 { score -= 15.0 }
        else if file.lineCount > 300 { score -= 8.0 }
        score = max(0, min(100, score))

        return FileQuality(
            file:                file,
            score:               score,
            commentRatio:        ratio,
            avgFunctionLength:   avgLen,
            longFunctionCount:   longFuncs,
            complexFunctionCount: complexFuncs,
            issues:              issues
        )
    }
}
