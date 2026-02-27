import Foundation

class CodeAnalyzer {
    
    func analyzeProject(at url: URL) async -> [FileAnalysis] {
        var analyses: [FileAnalysis] = []
        
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }
            
            // .build, Pods, DerivedData 등 제외
            let path = fileURL.path
            if path.contains("/.build/") || 
               path.contains("/Pods/") || 
               path.contains("/DerivedData/") ||
               path.contains("/.swiftpm/") {
                continue
            }
            
            if let analysis = await analyzeFile(at: fileURL) {
                analyses.append(analysis)
            }
        }
        
        return analyses.sorted { $0.complexityScore > $1.complexityScore }
    }
    
    private func analyzeFile(at url: URL) async -> FileAnalysis? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        
        let lines = content.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        
        return FileAnalysis(
            fileName: url.lastPathComponent,
            filePath: url.path,
            lineCount: nonEmptyLines.count,
            functionCount: countFunctions(in: content),
            classCount: countOccurrences(of: "class ", in: content),
            structCount: countOccurrences(of: "struct ", in: content),
            enumCount: countOccurrences(of: "enum ", in: content),
            protocolCount: countOccurrences(of: "protocol ", in: content),
            propertyCount: countProperties(in: content),
            cyclomaticComplexity: calculateCyclomaticComplexity(in: content)
        )
    }
    
    private func countMatches(of pattern: String, in content: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(content.startIndex..., in: content)
        return regex.numberOfMatches(in: content, range: range)
    }

    private func countFunctions(in content: String) -> Int {
        let funcPattern = #"func\s+\w+"#
        let initPattern = #"init\s*\("#

        let funcCount = countMatches(of: funcPattern, in: content)
        let initCount = countMatches(of: initPattern, in: content)

        return funcCount + initCount
    }

    private func countProperties(in content: String) -> Int {
        let varPattern = #"(var|let)\s+\w+\s*:"#
        return countMatches(of: varPattern, in: content)
    }
    
    private func countOccurrences(of keyword: String, in content: String) -> Int {
        // 주석 제외하고 실제 선언만 카운트
        let lines = content.components(separatedBy: .newlines)
        var count = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") { continue }
            if trimmed.contains(keyword) && !trimmed.contains("//") {
                // 실제 선언인지 확인 (문자열 내부가 아닌지)
                let beforeComment = trimmed.components(separatedBy: "//")[0]
                if beforeComment.contains(keyword) {
                    count += 1
                }
            }
        }
        
        return count
    }
    
    private func calculateCyclomaticComplexity(in content: String) -> Int {
        // 순환 복잡도: 결정 포인트 개수 + 1
        // if, guard, for, while, case, catch, &&, ||, ? 등을 카운트
        
        var complexity = 1 // 기본 경로
        
        let keywords = ["if ", "else if", "guard ", "for ", "while ", "case ", "catch ", "&&", "||", "?"]
        
        for keyword in keywords {
            complexity += content.components(separatedBy: keyword).count - 1
        }
        
        return complexity
    }
    
    func generateSummary(from analyses: [FileAnalysis]) -> ProjectSummary {
        let totalLines = analyses.reduce(0) { $0 + $1.lineCount }
        let totalFunctions = analyses.reduce(0) { $0 + $1.functionCount }
        let avgComplexity = analyses.isEmpty ? 0 : 
            analyses.reduce(0.0) { $0 + $1.complexityScore } / Double(analyses.count)
        
        return ProjectSummary(
            totalFiles: analyses.count,
            totalLines: totalLines,
            totalFunctions: totalFunctions,
            averageComplexity: avgComplexity,
            mostComplexFile: analyses.max { $0.complexityScore < $1.complexityScore },
            largestFile: analyses.max { $0.lineCount < $1.lineCount }
        )
    }
}
