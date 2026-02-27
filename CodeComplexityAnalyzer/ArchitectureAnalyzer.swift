import Foundation

// MARK: - Layer

enum ArchLayer: String, CaseIterable {
    case view        = "View / UI"
    case viewModel   = "ViewModel"
    case model       = "Model / Entity"
    case useCase     = "UseCase"
    case repository  = "Repository"
    case service     = "Service"
    case coordinator = "Coordinator"
    case other       = "기타"

    var icon: String {
        switch self {
        case .view:        return "rectangle.on.rectangle"
        case .viewModel:   return "arrow.left.arrow.right.square"
        case .model:       return "cylinder"
        case .useCase:     return "gearshape.2"
        case .repository:  return "externaldrive"
        case .service:     return "bolt.horizontal"
        case .coordinator: return "map"
        case .other:       return "questionmark.square"
        }
    }

    // 레이어 계층 순서 (낮을수록 하위)
    var hierarchyLevel: Int {
        switch self {
        case .view:        return 4
        case .viewModel:   return 3
        case .coordinator: return 3
        case .useCase:     return 2
        case .service:     return 2
        case .repository:  return 1
        case .model:       return 0
        case .other:       return -1
        }
    }
}

// MARK: - Pattern

enum ArchPattern: String {
    case mvvm              = "MVVM"
    case mvc               = "MVC"
    case cleanArchitecture = "Clean Architecture"
    case viper             = "VIPER"
    case mvp               = "MVP"
    case mixed             = "혼합 패턴"
    case unknown           = "패턴 미분류"

    var icon: String {
        switch self {
        case .mvvm:              return "square.3.layers.3d.top.filled"
        case .mvc:               return "square.3.layers.3d"
        case .cleanArchitecture: return "circle.grid.3x3"
        case .viper:             return "pentagon"
        case .mvp:               return "diamond"
        case .mixed:             return "mosaic"
        case .unknown:           return "questionmark.circle"
        }
    }

    var description: String {
        switch self {
        case .mvvm:
            return "View-ViewModel-Model 분리. SwiftUI / Combine과 자연스럽게 어울리며 반응형 바인딩을 지원합니다."
        case .mvc:
            return "Model-View-Controller. 단순하지만 Controller가 비대해지는 Massive VC 문제가 발생하기 쉽습니다."
        case .cleanArchitecture:
            return "UseCase-Repository 레이어 분리. 의존성 방향이 안쪽을 향하며 테스트 용이성이 높습니다."
        case .viper:
            return "View-Interactor-Presenter-Entity-Router의 엄격한 분리. 보일러플레이트가 많으나 테스트 친화적입니다."
        case .mvp:
            return "Model-View-Presenter. View는 수동적으로 Presenter의 지시를 따르는 구조입니다."
        case .mixed:
            return "여러 패턴이 혼재합니다. 일관된 아키텍처 규칙 적용이 필요합니다."
        case .unknown:
            return "명확한 아키텍처 패턴을 감지하지 못했습니다. 레이어 구분을 도입하는 것을 권장합니다."
        }
    }
}

// MARK: - FileLayerInfo

struct FileLayerInfo: Identifiable {
    let id      = UUID()
    let file:    FileAnalysis
    let layer:   ArchLayer
    let reasons: [String]
}

// MARK: - ArchIssue

struct ArchIssue: Identifiable {
    let id = UUID()

    enum IssueType: String {
        case massiveViewController = "Massive ViewController"
        case godObject             = "God Object"
        case layerViolation        = "레이어 위반"
        case singletonAbuse        = "싱글턴 남용"
        case namingMismatch        = "명명 규칙 불일치"
        case missingProtocol       = "프로토콜 미사용"
        case mixedConcerns         = "책임 혼재"

        var icon: String {
            switch self {
            case .massiveViewController: return "rectangle.compress.vertical"
            case .godObject:             return "tornado"
            case .layerViolation:        return "arrow.up.and.down.and.arrow.left.and.right"
            case .singletonAbuse:        return "lock.shield"
            case .namingMismatch:        return "textformat.abc"
            case .missingProtocol:       return "puzzlepiece.extension"
            case .mixedConcerns:         return "shuffle"
            }
        }
    }

    enum Severity: String, CaseIterable, Comparable {
        case high   = "높음"
        case medium = "중간"
        case low    = "낮음"

        static func < (lhs: Severity, rhs: Severity) -> Bool {
            let order: [Severity] = [.high, .medium, .low]
            return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
        }
    }

    let type:        IssueType
    let severity:    Severity
    let fileName:    String
    let filePath:    String
    let description: String
    let suggestion:  String
}

// MARK: - ArchReport

struct ArchReport {
    let pattern:           ArchPattern
    let patternConfidence: Double       // 0.0 ~ 1.0
    let layerInfos:        [FileLayerInfo]
    let issues:            [ArchIssue]
    let healthScore:       Double       // 0 ~ 100
    let separationScore:   Double       // 레이어 분리 명확성
    let namingScore:       Double       // 명명 규칙 준수
    let dependencyScore:   Double       // 의존 방향 준수
}

// MARK: - Analyzer

struct ArchitectureAnalyzer {

    func analyze(files: [FileAnalysis], edges: [DependencyEdge]) -> ArchReport {
        // 파일 내용 일괄 로드
        var contents = [String: String]()
        for f in files {
            contents[f.filePath] = (try? String(contentsOf: URL(fileURLWithPath: f.filePath), encoding: .utf8)) ?? ""
        }

        let layerInfos        = files.map { classifyFile($0, content: contents[$0.filePath] ?? "") }
        let (pattern, conf)   = detectPattern(layerInfos: layerInfos)
        let issues            = detectIssues(layerInfos: layerInfos, files: files,
                                             contents: contents, edges: edges)

        let sepScore  = calcSeparationScore(layerInfos: layerInfos)
        let nameScore = calcNamingScore(layerInfos: layerInfos)
        let depScore  = calcDependencyScore(layerInfos: layerInfos, edges: edges)
        let health    = (sepScore + nameScore + depScore) / 3.0

        return ArchReport(
            pattern:           pattern,
            patternConfidence: conf,
            layerInfos:        layerInfos,
            issues:            issues,
            healthScore:       health,
            separationScore:   sepScore,
            namingScore:       nameScore,
            dependencyScore:   depScore
        )
    }

    // MARK: - Layer Classification

    private func classifyFile(_ file: FileAnalysis, content: String) -> FileLayerInfo {
        let base = file.fileName.replacingOccurrences(of: ".swift", with: "")
        let low  = base.lowercased()
        var reasons = [String]()

        func make(_ layer: ArchLayer, _ reason: String) -> FileLayerInfo {
            return FileLayerInfo(file: file, layer: layer, reasons: [reason])
        }

        // ── 이름 기반 (최우선) ─────────────────────────────────────────────
        if low.hasSuffix("viewmodel")   { return make(.viewModel,   "파일명이 'ViewModel'로 끝남") }
        if low.hasSuffix("viewcontroller") || low.hasSuffix("vc") {
            return make(.view, "파일명에 'ViewController' 포함")
        }
        if low.hasSuffix("usecase")     { return make(.useCase,     "파일명이 'UseCase'로 끝남") }
        if low.hasSuffix("interactor")  { return make(.useCase,     "파일명이 'Interactor'로 끝남") }
        if low.hasSuffix("repository")  { return make(.repository,  "파일명이 'Repository'로 끝남") }
        if low.hasSuffix("datasource")  { return make(.repository,  "파일명이 'DataSource'로 끝남") }
        if low.hasSuffix("coordinator") { return make(.coordinator, "파일명이 'Coordinator'로 끝남") }
        if low.hasSuffix("router")      { return make(.coordinator, "파일명이 'Router'로 끝남") }
        if low.hasSuffix("presenter")   { return make(.viewModel,   "파일명이 'Presenter'로 끝남") }
        if low.hasSuffix("service")     { return make(.service,     "파일명이 'Service'로 끝남") }
        if low.hasSuffix("manager")     { return make(.service,     "파일명이 'Manager'로 끝남") }
        if low.hasSuffix("helper") || low.hasSuffix("util") || low.hasSuffix("utils") {
            return make(.service, "파일명이 'Helper/Util'로 끝남")
        }
        if low.hasSuffix("entity")      { return make(.model, "파일명이 'Entity'로 끝남") }
        if low.hasSuffix("model") && !low.contains("viewmodel") {
            return make(.model, "파일명이 'Model'로 끝남")
        }
        if low.hasSuffix("dto")         { return make(.model, "파일명이 'DTO'로 끝남") }
        if low.hasSuffix("view") && !low.contains("viewcontroller") {
            return make(.view, "파일명이 'View'로 끝남")
        }

        // ── 내용 기반 ──────────────────────────────────────────────────────
        if content.contains(": ObservableObject") || content.contains("@Published") {
            reasons.append("ObservableObject / @Published 사용")
            return FileLayerInfo(file: file, layer: .viewModel, reasons: reasons)
        }
        if content.contains(": View {") || content.contains(": View\n") {
            reasons.append("SwiftUI View 프로토콜 준수")
            return FileLayerInfo(file: file, layer: .view, reasons: reasons)
        }
        if content.contains(": UIViewController") {
            reasons.append("UIViewController 상속")
            return FileLayerInfo(file: file, layer: .view, reasons: reasons)
        }
        if content.contains("import SwiftUI") || content.contains("import UIKit") {
            reasons.append("SwiftUI / UIKit import 감지")
            return FileLayerInfo(file: file, layer: .view, reasons: reasons)
        }

        // ── 기본값 ────────────────────────────────────────────────────────
        reasons.append("UI 프레임워크 미사용 → Model/Entity 추정")
        return FileLayerInfo(file: file, layer: .model, reasons: reasons)
    }

    // MARK: - Pattern Detection

    private func detectPattern(layerInfos: [FileLayerInfo]) -> (ArchPattern, Double) {
        let counts = Dictionary(grouping: layerInfos, by: { $0.layer }).mapValues { $0.count }
        let total  = Double(layerInfos.count)
        guard total > 0 else { return (.unknown, 0) }

        let vm    = Double(counts[.viewModel]   ?? 0)
        let uc    = Double(counts[.useCase]     ?? 0)
        let repo  = Double(counts[.repository]  ?? 0)
        let coord = Double(counts[.coordinator] ?? 0)
        let view  = Double(counts[.view]        ?? 0)

        // Clean Architecture: UseCase + Repository 모두 있을 때
        if uc > 0 && repo > 0 {
            let conf = min(1.0, (uc + repo) / total * 3.0)
            return (.cleanArchitecture, conf)
        }
        // MVVM: ViewModel 존재, 그리고 UseCase/Repo 없음
        if vm > 0 && uc == 0 && repo == 0 {
            let conf = min(1.0, vm / total * 3.5)
            return (.mvvm, conf)
        }
        // MVVM + Coordinator
        if vm > 0 && coord > 0 {
            let conf = min(1.0, (vm + coord) / total * 3.0)
            return (.mvvm, conf * 0.9)
        }
        // MVC: View/VC 있지만 ViewModel 없음
        if view > 0 && vm == 0 {
            let conf = min(1.0, view / total * 2.5)
            return (.mvc, conf)
        }
        // 여러 패턴이 섞인 경우
        if vm > 0 && (uc > 0 || repo > 0) {
            return (.mixed, 0.5)
        }
        return (.unknown, 0.2)
    }

    // MARK: - Issue Detection

    private func detectIssues(layerInfos: [FileLayerInfo],
                              files: [FileAnalysis],
                              contents: [String: String],
                              edges: [DependencyEdge]) -> [ArchIssue] {
        var issues = [ArchIssue]()
        let layerMap = Dictionary(uniqueKeysWithValues: layerInfos.map { ($0.file.filePath, $0) })

        for info in layerInfos {
            let content = contents[info.file.filePath] ?? ""
            let file    = info.file
            let name    = file.fileName.replacingOccurrences(of: ".swift", with: "")
            let low     = name.lowercased()

            // ── 1. Massive ViewController ──────────────────────────────────
            if (low.contains("viewcontroller") || low.hasSuffix("vc"))
                && file.lineCount > 400 {
                issues.append(ArchIssue(
                    type:        .massiveViewController,
                    severity:    .high,
                    fileName:    file.fileName,
                    filePath:    file.filePath,
                    description: "ViewController \(file.lineCount)줄 · 함수 \(file.functionCount)개 — Massive ViewController 안티패턴입니다.",
                    suggestion:  "비즈니스 로직은 ViewModel로, 재사용 UI는 Custom View로 추출하세요.\n· ViewModel에 @Published 프로퍼티로 상태를 분리\n· 500줄 초과 시 기능별 Extension으로 분리"
                ))
            }

            // ── 2. God Object ──────────────────────────────────────────────
            if file.lineCount > 500 && file.functionCount > 20
                && !low.contains("viewcontroller") {
                issues.append(ArchIssue(
                    type:        .godObject,
                    severity:    .high,
                    fileName:    file.fileName,
                    filePath:    file.filePath,
                    description: "\(file.lineCount)줄 · 함수 \(file.functionCount)개 — 단일 책임 원칙(SRP) 위반이 의심됩니다.",
                    suggestion:  "관련 기능을 별도 클래스/서비스로 분리하세요.\n· 네트워크 → NetworkService\n· 파싱 → DataMapper\n· 비즈니스 로직 → UseCase"
                ))
            }

            // ── 3. 레이어 위반 ─────────────────────────────────────────────
            switch info.layer {
            case .viewModel:
                if content.contains("import UIKit") {
                    issues.append(ArchIssue(
                        type:        .layerViolation,
                        severity:    .medium,
                        fileName:    file.fileName,
                        filePath:    file.filePath,
                        description: "ViewModel이 UIKit을 import합니다. ViewModel은 UI 프레임워크에 독립적이어야 합니다.",
                        suggestion:  "UIKit 의존성을 제거하고 Foundation만 사용하세요.\nUI 변환(UIColor, UIImage 등)은 View 레이어에서 처리하세요."
                    ))
                }
            case .model:
                if content.contains("import SwiftUI") || content.contains("import UIKit") {
                    issues.append(ArchIssue(
                        type:        .layerViolation,
                        severity:    .high,
                        fileName:    file.fileName,
                        filePath:    file.filePath,
                        description: "Model/Entity가 UI 프레임워크를 import합니다. 도메인 모델은 UI에 의존하면 안 됩니다.",
                        suggestion:  "UI import를 제거하세요.\nColor/Image 등 UI 타입이 필요하다면 ViewModel에서 변환 프로퍼티를 추가하세요."
                    ))
                }
            case .useCase:
                if content.contains("import SwiftUI") || content.contains("import UIKit") {
                    issues.append(ArchIssue(
                        type:        .layerViolation,
                        severity:    .high,
                        fileName:    file.fileName,
                        filePath:    file.filePath,
                        description: "UseCase/Interactor가 UI 프레임워크를 import합니다. 도메인 레이어는 UI에 독립적이어야 합니다.",
                        suggestion:  "UI import를 제거하고 순수 Swift / Foundation만 사용하세요."
                    ))
                }
            default:
                break
            }

            // ── 4. 명명 규칙 불일치 ────────────────────────────────────────
            if info.layer == .view && info.reasons.contains(where: { $0.contains("SwiftUI") || $0.contains("UIKit") }) {
                let hasViewInName = low.contains("view") || low.contains("controller")
                    || low.contains("scene") || low.contains("screen") || low.contains("page")
                if !hasViewInName {
                    issues.append(ArchIssue(
                        type:        .namingMismatch,
                        severity:    .low,
                        fileName:    file.fileName,
                        filePath:    file.filePath,
                        description: "View 코드를 포함하지만 파일명에 'View/Controller'가 없습니다.",
                        suggestion:  "파일명을 '\(name)View.swift'로 변경하거나 View 코드를 별도 파일로 분리하세요."
                    ))
                }
            }

            // ── 5. 프로토콜 미사용 ─────────────────────────────────────────
            if info.layer == .repository || info.layer == .useCase {
                let hasProtocol = content.contains("protocol ")
                let conformsToProtocol = content.range(
                    of: #"(?:class|struct)\s+\w+\s*:\s*\w+(?:Protocol|able|ing)"#,
                    options: .regularExpression
                ) != nil
                if !hasProtocol && !conformsToProtocol {
                    issues.append(ArchIssue(
                        type:        .missingProtocol,
                        severity:    .low,
                        fileName:    file.fileName,
                        filePath:    file.filePath,
                        description: "\(info.layer.rawValue)에 프로토콜이 정의되지 않았습니다. Mock 교체와 단위 테스트가 어렵습니다.",
                        suggestion:  "'\(name)Protocol'을 정의하고 DI를 사용하세요.\nprotocol \(name)Protocol {\n    // 공개 인터페이스\n}"
                    ))
                }
            }
        }

        // ── 6. 싱글턴 남용 (프로젝트 전체) ───────────────────────────────
        let singletonFiles = layerInfos.filter { info in
            let c = contents[info.file.filePath] ?? ""
            return c.contains("static let shared") || c.contains("static var shared")
        }
        if singletonFiles.count > 3 {
            let names = singletonFiles.prefix(3).map { $0.file.fileName }.joined(separator: ", ")
            issues.append(ArchIssue(
                type:        .singletonAbuse,
                severity:    .medium,
                fileName:    "\(names) 외 \(max(0, singletonFiles.count - 3))개",
                filePath:    singletonFiles.first?.file.filePath ?? "",
                description: "\(singletonFiles.count)개 파일에서 싱글턴 패턴이 감지되었습니다. 전역 상태 의존과 테스트 격리 어려움이 생길 수 있습니다.",
                suggestion:  "의존성 주입(DI)을 활용하세요.\n· 생성자 주입: init(service: ServiceProtocol)\n· Environment Object (SwiftUI)\n· DIContainer 패턴"
            ))
        }

        // ── 7. 의존성 방향 위반 (그래프 기반) ────────────────────────────
        for edge in edges {
            guard let fromInfo = layerMap[edge.fromFilePath],
                  let toInfo   = layerMap[edge.toFilePath] else { continue }
            let fromLevel = fromInfo.layer.hierarchyLevel
            let toLevel   = toInfo.layer.hierarchyLevel
            // 하위 레이어가 상위 레이어를 참조하면 위반 (역방향 의존)
            if toLevel > fromLevel + 1 && fromLevel >= 0 && toLevel >= 0 {
                // 이미 동일 파일에 대한 이슈가 없는지 확인
                let alreadyReported = issues.contains {
                    $0.type == .layerViolation && $0.filePath == edge.fromFilePath
                }
                if !alreadyReported {
                    issues.append(ArchIssue(
                        type:        .layerViolation,
                        severity:    .medium,
                        fileName:    fromInfo.file.fileName,
                        filePath:    fromInfo.file.filePath,
                        description: "하위 레이어('\(fromInfo.layer.rawValue)')가 상위 레이어('\(toInfo.layer.rawValue)')를 직접 참조합니다. 의존성 역전 원칙(DIP) 위반입니다.",
                        suggestion:  "Protocol을 도입해 의존 방향을 역전시키세요.\n\(fromInfo.file.fileName) → Protocol ← \(toInfo.file.fileName)"
                    ))
                }
            }
        }

        return issues.sorted { $0.severity < $1.severity }
    }

    // MARK: - Score Calculation

    private func calcSeparationScore(layerInfos: [FileLayerInfo]) -> Double {
        let total      = Double(layerInfos.count)
        guard total > 0 else { return 0 }
        let classified = Double(layerInfos.filter { $0.layer != .other }.count)
        return classified / total * 100.0
    }

    private func calcNamingScore(layerInfos: [FileLayerInfo]) -> Double {
        let total = Double(layerInfos.count)
        guard total > 0 else { return 0 }
        var correct = 0.0
        for info in layerInfos {
            let low = info.file.fileName.lowercased()
            switch info.layer {
            case .viewModel   where low.contains("viewmodel") || low.contains("presenter"): correct += 1
            case .view        where low.contains("view") || low.contains("controller") || low.contains("screen"): correct += 1
            case .useCase     where low.contains("usecase") || low.contains("interactor"): correct += 1
            case .repository  where low.contains("repository") || low.contains("datasource"): correct += 1
            case .model       where low.contains("model") || low.contains("entity") || low.contains("dto"): correct += 1
            case .service     where low.contains("service") || low.contains("manager") || low.contains("helper"): correct += 1
            case .coordinator where low.contains("coordinator") || low.contains("router"): correct += 1
            default: break
            }
        }
        return correct / total * 100.0
    }

    private func calcDependencyScore(layerInfos: [FileLayerInfo], edges: [DependencyEdge]) -> Double {
        guard !edges.isEmpty else { return 100.0 }
        let layerMap  = Dictionary(uniqueKeysWithValues: layerInfos.map { ($0.file.filePath, $0.layer) })
        var total     = 0, violations = 0
        for edge in edges {
            guard let f = layerMap[edge.fromFilePath],
                  let t = layerMap[edge.toFilePath],
                  f.hierarchyLevel >= 0, t.hierarchyLevel >= 0 else { continue }
            total += 1
            // 하위가 상위보다 두 단계 이상 건너뛰면 위반
            if t.hierarchyLevel > f.hierarchyLevel + 1 { violations += 1 }
        }
        guard total > 0 else { return 100.0 }
        return Double(total - violations) / Double(total) * 100.0
    }
}
