import Foundation

class CodeAnalyzer {

    func analyzeProject(at url: URL) async -> [FileAnalysis] {
        var analyses: [FileAnalysis] = []

        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey])

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == "swift" else { continue }

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
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Strip comments and string literals once; reuse for all counts.
        let code = stripNonCode(content)

        return FileAnalysis(
            fileName: url.lastPathComponent,
            filePath: url.path,
            lineCount: nonEmptyLines.count,
            functionCount: countFunctions(in: code),
            classCount: countDeclarations(keyword: "class ", in: code),
            structCount: countDeclarations(keyword: "struct ", in: code),
            enumCount: countDeclarations(keyword: "enum ", in: code),
            protocolCount: countDeclarations(keyword: "protocol ", in: code),
            propertyCount: countProperties(in: code),
            cyclomaticComplexity: calculateCyclomaticComplexity(in: code)
        )
    }

    // MARK: - Comment / String Stripping

    /// Returns source with comments and string literal *contents* removed,
    /// preserving newlines so that line-count-based metrics remain valid.
    func stripNonCode(_ source: String) -> String {
        let chars = Array(source)
        var result = [Character]()
        result.reserveCapacity(chars.count)
        var i = 0

        while i < chars.count {
            let c = chars[i]

            // ── Line comment  // … \n ────────────────────────────────────
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                while i < chars.count && chars[i] != "\n" { i += 1 }
                continue
            }

            // ── Block comment  /* … */ ───────────────────────────────────
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                i += 2
                while i < chars.count {
                    if chars[i] == "*" && i + 1 < chars.count && chars[i + 1] == "/" {
                        i += 2; break
                    }
                    // Preserve newlines so line numbers stay intact
                    if chars[i] == "\n" { result.append("\n") }
                    i += 1
                }
                continue
            }

            // ── Triple-quoted string  """…""" ────────────────────────────
            if c == "\"" && i + 2 < chars.count && chars[i + 1] == "\"" && chars[i + 2] == "\"" {
                i += 3
                while i < chars.count {
                    if chars[i] == "\"" && i + 2 < chars.count && chars[i + 1] == "\"" && chars[i + 2] == "\"" {
                        i += 3; break
                    }
                    if chars[i] == "\n" { result.append("\n") }
                    i += 1
                }
                continue
            }

            // ── Empty string  "" ─────────────────────────────────────────
            if c == "\"" && i + 1 < chars.count && chars[i + 1] == "\"" {
                i += 2; continue
            }

            // ── Regular string  "…" ──────────────────────────────────────
            if c == "\"" {
                i += 1
                while i < chars.count && chars[i] != "\"" {
                    if chars[i] == "\\" { i += 1 } // skip escaped character
                    if i < chars.count { i += 1 }
                }
                if i < chars.count { i += 1 } // skip closing "
                continue
            }

            result.append(c)
            i += 1
        }

        return String(result)
    }

    // MARK: - Counting (all operate on pre-stripped code)

    private func countMatches(of pattern: String, in code: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return 0 }
        return re.numberOfMatches(in: code, range: NSRange(code.startIndex..., in: code))
    }

    private func countFunctions(in code: String) -> Int {
        countMatches(of: #"\bfunc\s+\w+"#, in: code) +
        countMatches(of: #"\binit\s*\("#, in: code)
    }

    private func countProperties(in code: String) -> Int {
        countMatches(of: #"\b(var|let)\s+\w+\s*[=:{]"#, in: code)
    }

    private func countDeclarations(keyword: String, in code: String) -> Int {
        // Split on keyword; the count of splits minus 1 is the number of occurrences.
        code.components(separatedBy: keyword).count - 1
    }

    // MARK: - Cyclomatic Complexity (on stripped code)

    /// McCabe cyclomatic complexity: 1 + number of independent decision paths.
    /// Decision points: if, guard, for, while, repeat, switch case, catch, &&, ||.
    private func calculateCyclomaticComplexity(in code: String) -> Int {
        var n = 1

        // Keyword-based counts (word boundaries where applicable)
        let wordKeywords = ["if", "else if", "guard", "for", "while", "repeat", "catch"]
        for kw in wordKeywords {
            // Use space/newline boundaries to avoid partial matches
            n += code.components(separatedBy: " \(kw) ").count - 1
            n += code.components(separatedBy: "\n\(kw) ").count - 1
            n += code.components(separatedBy: "(\(kw) ").count - 1
        }

        // Switch case lines: "case X:" patterns (not enum case declarations)
        n += countMatches(of: #"^\s*case\s+[^:]+:"#, in: code)

        // Logical operators — each adds an independent path
        n += code.components(separatedBy: "&&").count - 1
        n += code.components(separatedBy: "||").count - 1

        return n
    }

    // MARK: - Summary

    func generateSummary(from analyses: [FileAnalysis]) -> ProjectSummary {
        let totalLines     = analyses.reduce(0) { $0 + $1.lineCount }
        let totalFunctions = analyses.reduce(0) { $0 + $1.functionCount }
        let avgComplexity  = analyses.isEmpty ? 0.0 :
            analyses.reduce(0.0) { $0 + Double($1.cyclomaticComplexity) } / Double(analyses.count)

        return ProjectSummary(
            totalFiles:       analyses.count,
            totalLines:       totalLines,
            totalFunctions:   totalFunctions,
            averageComplexity: avgComplexity,
            mostComplexFile:  analyses.max { $0.complexityScore < $1.complexityScore },
            largestFile:      analyses.max { $0.lineCount < $1.lineCount }
        )
    }
}
