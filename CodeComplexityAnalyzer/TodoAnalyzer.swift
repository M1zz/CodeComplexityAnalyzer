import Foundation

// MARK: - TodoItem

struct TodoItem: Identifiable {
    let id = UUID()

    enum Kind: String, CaseIterable {
        case warning = "WARNING"
        case fixme   = "FIXME"
        case hack    = "HACK"
        case todo    = "TODO"
        case mark    = "MARK"

        var icon: String {
            switch self {
            case .warning: return "exclamationmark.octagon.fill"
            case .fixme:   return "wrench.and.screwdriver.fill"
            case .hack:    return "bolt.trianglebadge.exclamationmark.fill"
            case .todo:    return "checkmark.circle"
            case .mark:    return "bookmark.fill"
            }
        }

        // 정렬 우선순위 (낮을수록 먼저)
        var priority: Int {
            switch self { case .warning: return 0; case .fixme: return 1
                          case .hack: return 2; case .todo: return 3; case .mark: return 4 }
        }
    }

    let kind:       Kind
    let fileName:   String
    let filePath:   String
    let lineNumber: Int
    let content:    String
}

// MARK: - Analyzer

struct TodoAnalyzer {

    func analyze(files: [FileAnalysis]) -> [TodoItem] {
        let pattern = #"//\s*(TODO|FIXME|HACK|WARNING|MARK)\s*:?\s*(.*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return [] }

        var items = [TodoItem]()
        for file in files {
            guard let raw = try? String(contentsOfFile: file.filePath, encoding: .utf8) else { continue }
            let lines = raw.components(separatedBy: "\n")
            for (i, line) in lines.enumerated() {
                let ns = line as NSString
                let range = NSRange(location: 0, length: ns.length)
                guard let m = regex.firstMatch(in: line, range: range) else { continue }

                let kindStr = ns.substring(with: m.range(at: 1)).uppercased()
                let text    = m.range(at: 2).location != NSNotFound
                    ? ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
                    : ""
                guard let kind = TodoItem.Kind(rawValue: kindStr) else { continue }

                items.append(TodoItem(
                    kind:       kind,
                    fileName:   file.fileName,
                    filePath:   file.filePath,
                    lineNumber: i + 1,
                    content:    text.isEmpty ? "(내용 없음)" : text
                ))
            }
        }
        return items.sorted {
            $0.kind.priority != $1.kind.priority
                ? $0.kind.priority < $1.kind.priority
                : $0.fileName < $1.fileName
        }
    }
}
