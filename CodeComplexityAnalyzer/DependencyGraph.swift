import Foundation

// MARK: - Model

struct DependencyEdge: Identifiable {
    let id = UUID()
    let fromFilePath: String
    let toFilePath: String
    let sharedTypes: [String]
}

// MARK: - Dependency Stats

struct DependencyStats {
    let cyclicNodes: Set<String>
    let inDegree:    [String: Int]   // 이 파일을 참조하는 파일 수
    let outDegree:   [String: Int]   // 이 파일이 참조하는 파일 수
    let totalEdges:  Int
    let isolatedFilePaths: [String]  // 연결이 없는 파일
    let orphanedFilePaths: [String]  // inDegree == 0인 파일 (진입점 제외)

    var mostReferenced: (path: String, count: Int)? {
        inDegree.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }
    var mostReferencing: (path: String, count: Int)? {
        outDegree.max(by: { $0.value < $1.value }).map { ($0.key, $0.value) }
    }

    static func compute(analyses: [FileAnalysis], edges: [DependencyEdge]) -> DependencyStats {
        var inDeg  = [String: Int]()
        var outDeg = [String: Int]()
        var connected = Set<String>()

        for edge in edges {
            outDeg[edge.fromFilePath, default: 0] += 1
            inDeg[edge.toFilePath,   default: 0] += 1
            connected.insert(edge.fromFilePath)
            connected.insert(edge.toFilePath)
        }

        let isolated = analyses
            .filter { !connected.contains($0.filePath) }
            .map { $0.filePath }

        let entryPointSuffixes = ["App.swift", "AppDelegate.swift", "main.swift", "SceneDelegate.swift"]
        // 프로젝트 내 모든 파일명(확장자 제거) — extension 대상 타입명 비교에 사용
        let projectTypeNames = Set(analyses.map {
            URL(fileURLWithPath: $0.filePath).deletingPathExtension().lastPathComponent
        })

        // 다른 파일들의 내용을 미리 로드 (static 멤버 사용 여부 검사용)
        let otherContents: [(path: String, content: String)] = analyses.compactMap { a in
            guard let c = try? String(contentsOf: URL(fileURLWithPath: a.filePath), encoding: .utf8) else { return nil }
            return (a.filePath, c)
        }

        let orphaned = analyses.filter { file in
            // 진입점 제외
            guard !entryPointSuffixes.contains(where: { file.fileName.hasSuffix($0) }) else { return false }
            // 다른 파일이 이 파일의 타입을 참조하면 고아 아님
            guard inDeg[file.filePath] == nil else { return false }
            // 이 파일이 다른 파일의 타입을 참조하면 (outDeg > 0) 고아 아님
            if (outDeg[file.filePath] ?? 0) > 0 { return false }

            guard let content = (otherContents.first { $0.path == file.filePath }?.content) else { return true }

            // extension으로 프로젝트 파일명과 일치하는 타입을 확장하면 고아 아님
            let extendedNames = DependencyAnalyzer.extractExtensionTypeNames(from: content)
            if extendedNames.contains(where: { projectTypeNames.contains($0) }) { return false }

            // static 멤버(let/var/func)나 최상위 함수 이름이 다른 파일에서 사용되면 고아 아님
            // — extension Notification.Name { static let xxx } 같은 패턴 대응
            let exportedNames = DependencyAnalyzer.extractExportedMemberNames(from: content)
            if !exportedNames.isEmpty {
                for other in otherContents where other.path != file.filePath {
                    if exportedNames.contains(where: { DependencyAnalyzer.containsWord($0, in: other.content) }) {
                        return false
                    }
                }
            }

            return true
        }.map(\.filePath)

        return DependencyStats(
            cyclicNodes:       DependencyAnalyzer.findCyclicNodes(from: edges),
            inDegree:          inDeg,
            outDegree:         outDeg,
            totalEdges:        edges.count,
            isolatedFilePaths: isolated,
            orphanedFilePaths: orphaned
        )
    }
}

// MARK: - Analyzer

class DependencyAnalyzer {

    func analyze(files: [FileAnalysis]) -> [DependencyEdge] {
        var typeToFile: [String: String] = [:]
        for file in files {
            guard let content = try? String(contentsOf: URL(fileURLWithPath: file.filePath), encoding: .utf8) else { continue }
            for name in Self.extractTypeNames(from: content) where name.count >= 3 {
                typeToFile[name] = file.filePath
            }
        }

        var edges: [DependencyEdge] = []
        for file in files {
            guard let content = try? String(contentsOf: URL(fileURLWithPath: file.filePath), encoding: .utf8) else { continue }

            var deps: [String: [String]] = [:]
            for (typeName, origin) in typeToFile where origin != file.filePath {
                if Self.containsWord(typeName, in: content) {
                    deps[origin, default: []].append(typeName)
                }
            }
            for (target, types) in deps {
                edges.append(DependencyEdge(
                    fromFilePath: file.filePath,
                    toFilePath:   target,
                    sharedTypes:  types.sorted()
                ))
            }
        }
        return edges
    }

    // MARK: - 순환 의존성 탐지 (Kosaraju SCC, 반복적 DFS)

    static func findCyclicNodes(from edges: [DependencyEdge]) -> Set<String> {
        var fwd = [String: [String]]()
        var rev = [String: [String]]()
        var allNodes = Set<String>()

        for edge in edges {
            fwd[edge.fromFilePath, default: []].append(edge.toFilePath)
            rev[edge.toFilePath,   default: []].append(edge.fromFilePath)
            allNodes.insert(edge.fromFilePath)
            allNodes.insert(edge.toFilePath)
        }

        // 1단계: 정방향 DFS → 완료 순서 기록
        var visited = Set<String>()
        var finishOrder = [String]()

        for start in allNodes where !visited.contains(start) {
            var stack: [(String, Int)] = [(start, 0)]
            visited.insert(start)
            while !stack.isEmpty {
                let (node, ni) = stack[stack.count - 1]
                let neighbors = fwd[node] ?? []
                if ni < neighbors.count {
                    stack[stack.count - 1].1 += 1
                    let next = neighbors[ni]
                    if !visited.contains(next) {
                        visited.insert(next)
                        stack.append((next, 0))
                    }
                } else {
                    stack.removeLast()
                    finishOrder.append(node)
                }
            }
        }

        // 2단계: 역방향 DFS (완료 역순) → SCC 식별
        var compOf  = [String: Int]()
        var compId  = 0
        visited = []

        for start in finishOrder.reversed() where !visited.contains(start) {
            var queue = [start]
            visited.insert(start)
            compOf[start] = compId
            var qi = 0
            while qi < queue.count {
                let node = queue[qi]; qi += 1
                for next in (rev[node] ?? []) where !visited.contains(next) {
                    visited.insert(next)
                    compOf[next] = compId
                    queue.append(next)
                }
            }
            compId += 1
        }

        // 크기 > 1인 SCC = 순환 의존성
        var compSize = [Int: Int]()
        for (_, id) in compOf { compSize[id, default: 0] += 1 }

        return Set(compOf.compactMap { node, id in compSize[id]! > 1 ? node : nil })
    }

    // MARK: - 전이적 의존 탐색

    /// start가 직·간접적으로 의존하는 모든 파일 경로
    static func transitivelyReachable(from start: String, using edges: [DependencyEdge]) -> Set<String> {
        var fwd = [String: [String]]()
        for edge in edges { fwd[edge.fromFilePath, default: []].append(edge.toFilePath) }

        var result = Set<String>()
        var queue = [start], qi = 0
        while qi < queue.count {
            let node = queue[qi]; qi += 1
            for next in (fwd[node] ?? []) where next != start && !result.contains(next) {
                result.insert(next)
                queue.append(next)
            }
        }
        return result
    }

    /// target을 직·간접적으로 의존하는 모든 파일 경로
    static func transitivelyDependent(on target: String, using edges: [DependencyEdge]) -> Set<String> {
        var rev = [String: [String]]()
        for edge in edges { rev[edge.toFilePath, default: []].append(edge.fromFilePath) }

        var result = Set<String>()
        var queue = [target], qi = 0
        while qi < queue.count {
            let node = queue[qi]; qi += 1
            for prev in (rev[node] ?? []) where prev != target && !result.contains(prev) {
                result.insert(prev)
                queue.append(prev)
            }
        }
        return result
    }

    // MARK: - Private

    static func extractTypeNames(from content: String) -> [String] {
        let pattern = #"(?:class|struct|enum|protocol|actor|typealias)\s+(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[r])
        }
    }

    /// static let/var/func 및 최상위 func 이름 추출 (길이 3 이상)
    /// extension Notification.Name { static let xxx } 같은 패턴의 사용 추적에 사용
    static func extractExportedMemberNames(from content: String) -> [String] {
        let pattern = #"(?:static\s+)?(?:let|var|func)\s+(`?)(\w+)\1"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard let r = Range(match.range(at: 2), in: content) else { return nil }
            let name = String(content[r])
            // 너무 짧거나 Swift 키워드처럼 흔한 이름은 제외
            return name.count >= 4 ? name : nil
        }
    }

    /// `extension TypeName` 패턴에서 확장 대상 타입명 추출
    static func extractExtensionTypeNames(from content: String) -> [String] {
        let pattern = #"extension\s+(\w+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(content.startIndex..., in: content)
        return regex.matches(in: content, range: range).compactMap { match in
            guard let r = Range(match.range(at: 1), in: content) else { return nil }
            return String(content[r])
        }
    }

    static func containsWord(_ word: String, in content: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: word)
        guard let regex = try? NSRegularExpression(pattern: "\\b\(escaped)\\b") else { return false }
        return regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)) != nil
    }
}
