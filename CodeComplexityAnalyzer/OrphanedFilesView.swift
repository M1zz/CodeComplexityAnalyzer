import SwiftUI
import AppKit

// MARK: - OrphanedFilesView

struct OrphanedFilesView: View {
    let files: [FileAnalysis]

    var body: some View {
        if files.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("모든 파일이 프로젝트에서 사용되고 있습니다")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("참조되지 않는 파일이 발견되지 않았습니다.")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                infoBanner
                Divider()
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(files.sorted { $0.lineCount > $1.lineCount }) { file in
                            OrphanedFileRow(file: file)
                        }
                    }
                }
            }
        }
    }

    private var infoBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("아래 파일들은 프로젝트 내 어떤 파일도 참조하지 않습니다. 삭제하거나 사용처를 연결하세요.")
                    .font(.callout)
                    .fontWeight(.medium)
                Spacer()
                Text("\(files.count)개 파일")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(4)
            }
            HStack {
                Text("진입점 파일(~App.swift, AppDelegate.swift, main.swift)은 자동으로 제외됩니다.")
                    .font(.body)
                    .foregroundColor(.secondary)
                Spacer()
                BulkDeletePromptButton(files: files)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.08))
    }
}

// MARK: - OrphanedFileRow

struct OrphanedFileRow: View {
    let file: FileAnalysis

    var body: some View {
        HStack(spacing: 12) {
            // 왼쪽 인디케이터 바
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.4))
                .frame(width: 4)
                .frame(height: 40)

            Image(systemName: "xmark.doc")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 24)

            // 파일 정보
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .lineLimit(1)
                Text(file.filePath)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // 지표 배지
            metricBadge(value: "\(file.lineCount)", label: "lines")
            metricBadge(value: "\(file.functionCount)", label: "funcs")

            // AI 프롬프트 복사 / Finder에서 보기
            OrphanCopyPromptButton(file: file)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(
                    [URL(fileURLWithPath: file.filePath)]
                )
            } label: {
                Label("Finder에서 보기", systemImage: "folder")
                    .font(.body)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
    }

    private func metricBadge(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
        }
        .frame(width: 48)
    }
}

// MARK: - BulkDeletePromptButton

fileprivate struct BulkDeletePromptButton: View {
    let files: [FileAnalysis]
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(makePrompt(), forType: .string)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { copied = false }
            }
        } label: {
            Label(
                copied ? "복사됨!" : "전체 삭제 프롬프트 복사",
                systemImage: copied ? "checkmark.circle.fill" : "trash.slash"
            )
            .font(.body).fontWeight(.semibold)
            .foregroundColor(copied ? .green : .red)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private func makePrompt() -> String {
        let fileList = files
            .sorted { $0.lineCount > $1.lineCount }
            .enumerated()
            .map { i, f in "\(i + 1). \(f.filePath) (\(f.lineCount)줄, \(f.functionCount)개 함수)" }
            .joined(separator: "\n")

        return """
        아래 Swift 파일들은 프로젝트 내 어떤 파일도 참조하지 않는 고아(orphaned) 파일입니다.
        각 파일을 검토하고, 안전하게 삭제 가능한지 판단해줘.
        삭제하면 안 되는 파일이 있다면 이유와 함께 알려줘.
        삭제 가능한 파일은 실제로 삭제하는 명령어(rm)도 함께 제시해줘.

        고아 파일 목록 (\(files.count)개):
        \(fileList)
        """
    }
}

// MARK: - OrphanCopyPromptButton

fileprivate struct OrphanCopyPromptButton: View {
    let file: FileAnalysis
    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(makePrompt(), forType: .string)
            withAnimation { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { copied = false }
            }
        } label: {
            Label(
                copied ? "복사됨!" : "AI 프롬프트 복사",
                systemImage: copied ? "checkmark.circle.fill" : "doc.on.clipboard"
            )
            .font(.body).fontWeight(.semibold)
            .foregroundColor(copied ? .green : .accentColor)
        }
        .buttonStyle(.bordered).controlSize(.small)
    }

    private func makePrompt() -> String {
        """
        다음 Swift 파일이 프로젝트 내 어떤 파일도 참조하지 않아.

        파일: \(file.filePath)
        크기: \(file.lineCount)줄, \(file.functionCount)개 함수

        이 파일을 삭제해도 되는지, 아니면 어딘가에 연결해야 하는지 판단해줘.
        파일이 필요하다면 어디서 사용해야 하는지도 알려줘.
        """
    }
}
