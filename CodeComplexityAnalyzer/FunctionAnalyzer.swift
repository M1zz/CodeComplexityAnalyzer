import Foundation

// MARK: - FunctionInfo

struct FunctionInfo: Identifiable {
    let id = UUID()
    let name:       String
    let signature:  String
    let fileName:   String
    let filePath:   String
    let startLine:  Int
    let lineCount:  Int
    let paramCount: Int
    let cc:         Int   // cyclomatic complexity

    var ccLevel: ComplexityLevel {
        switch cc {
        case ..<5:  return .low
        case 5..<10: return .medium
        case 10..<20: return .high
        default:     return .veryHigh
        }
    }
}

// MARK: - Analyzer

struct FunctionAnalyzer {

    func analyze(files: [FileAnalysis]) -> [FunctionInfo] {
        files.flatMap { parse($0) }
             .sorted { $0.cc > $1.cc }
    }

    // MARK: - Parse

    private func parse(_ file: FileAnalysis) -> [FunctionInfo] {
        guard let raw = try? String(contentsOfFile: file.filePath, encoding: .utf8) else { return [] }
        let lines = raw.components(separatedBy: "\n")
        var results = [FunctionInfo]()

        let pattern = #"(?:func|init)\s+(\w+)\s*(?:<[^>]*>)?\s*\(([^)]*(?:\([^)]*\)[^)]*)*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for (i, line) in lines.enumerated() {
            let ns = line as NSString
            guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }

            let name = m.range(at: 1).location != NSNotFound
                ? ns.substring(with: m.range(at: 1)) : "unknown"

            let paramStr = m.range(at: 2).location != NSNotFound
                ? ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces) : ""
            let params = paramStr.isEmpty ? 0 : paramStr.components(separatedBy: ":").count - 1

            let bodyEnd  = findEnd(lines: lines, from: i)
            let lineCount = max(1, bodyEnd - i + 1)
            let body      = lines[i ... min(bodyEnd, lines.count - 1)].joined(separator: "\n")

            results.append(FunctionInfo(
                name:      name,
                signature: line.trimmingCharacters(in: .whitespaces),
                fileName:  file.fileName,
                filePath:  file.filePath,
                startLine: i + 1,
                lineCount: lineCount,
                paramCount: params,
                cc:        calcCC(body)
            ))
        }
        return results
    }

    private func findEnd(lines: [String], from start: Int) -> Int {
        var depth = 0; var opened = false
        let limit = min(start + 400, lines.count)
        for i in start ..< limit {
            for ch in lines[i] {
                if ch == "{" { depth += 1; opened = true }
                else if ch == "}" { depth -= 1 }
            }
            if opened && depth == 0 { return i }
        }
        return min(start + 50, lines.count - 1)
    }

    private func calcCC(_ body: String) -> Int {
        let tokens = ["if ", "else if ", "guard ", "for ", "while ", "switch ",
                      "case ", " catch ", " && ", " || ", "?? "]
        return 1 + tokens.reduce(0) { $0 + body.components(separatedBy: $1).count - 1 }
    }
}
