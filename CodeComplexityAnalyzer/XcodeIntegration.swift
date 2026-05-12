import AppKit
import Foundation

/// Opens the given Swift file in Xcode. Jumps to a specific line when provided.
func openInXcode(_ filePath: String, line: Int? = nil) {
    let task = Process()
    task.launchPath = "/usr/bin/xed"
    if let line {
        task.arguments = ["--line", "\(line)", filePath]
    } else {
        task.arguments = [filePath]
    }
    try? task.run()
}

/// Reveals the given path in Finder (selects it in the enclosing folder).
func revealInFinder(_ filePath: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
}
