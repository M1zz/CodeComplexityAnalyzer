import SwiftUI

struct MetricInfoButton: View {
    let key: String
    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover = true
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover) {
            if let explanation = MetricExplanation.catalog[key] {
                VStack(alignment: .leading, spacing: 8) {
                    Text(explanation.plainTerm)
                        .font(.headline)
                    Text(explanation.explanation)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .frame(width: 280)
            } else {
                Text("설명이 없습니다")
                    .padding()
                    .frame(width: 280)
            }
        }
    }
}
