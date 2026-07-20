import SwiftUI
import PectoKit

/// Right-hand pane: the selected task's change history.
struct ChangesPanel: View {
    let model: AppModel
    let task: TaskSummary

    var body: some View {
        let snapshots = model.snapshots(for: task.path)
        Group {
            if snapshots.isEmpty {
                ContentUnavailableView(
                    "No changes yet",
                    systemImage: "plus.forwardslash.minus",
                    description: Text("Save the task and each version will show up here.")
                )
            } else {
                List(snapshots) { snapshot in
                    SnapshotEntry(
                        model: model,
                        snapshot: snapshot,
                        isLatest: snapshot.id == snapshots.first?.id
                    )
                }
                .listStyle(.inset)
            }
        }
    }
}

private func timestamp(_ milliseconds: Int) -> Text {
    Text(
        Date(timeIntervalSince1970: Double(milliseconds) / 1000),
        format: .dateTime.month(.abbreviated).day().hour().minute()
    )
}

// MARK: - Snapshot entry

private struct SnapshotEntry: View {
    let model: AppModel
    let snapshot: SnapshotRecord
    let isLatest: Bool
    @State private var isExpanded = false
    @State private var isConfirmingRestore = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let detail = model.snapshotDetail(id: snapshot.id) {
                    diffView(before: detail.prevContent, after: detail.content)
                }
                if !isLatest {
                    Button("Restore This Version") {
                        isConfirmingRestore = true
                    }
                    .confirmationDialog(
                        "Restore this version?",
                        isPresented: $isConfirmingRestore
                    ) {
                        Button("Restore") { model.restoreSnapshot(id: snapshot.id) }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The task file is overwritten with this version. The current content stays in the history.")
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 6) {
                Text(kindLabel)
                timestamp(snapshot.at)
                    .foregroundStyle(.secondary)
                Spacer()
                if snapshot.kind != .renamed {
                    Text("+\(snapshot.linesAdded)")
                        .foregroundStyle(.green)
                    Text("−\(snapshot.linesRemoved)")
                        .foregroundStyle(.red)
                }
            }
            .font(.callout)
        }
    }

    private var kindLabel: String {
        switch snapshot.kind {
        case .created: "Created"
        case .edited: "Edited"
        case .restored: "Restored"
        case .renamed: "Renamed from \(snapshot.renamedFrom ?? "?")"
        }
    }

    private func diffView(before: String, after: String) -> some View {
        let lines = diffLines(before: before, after: after)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(prefix(for: line.type) + (line.text.isEmpty ? " " : line.text))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(background(for: line.type))
            }
        }
        .textSelection(.enabled)
    }

    private func prefix(for type: DiffLine.Kind) -> String {
        switch type {
        case .same: "  "
        case .added: "+ "
        case .removed: "− "
        }
    }

    private func background(for type: DiffLine.Kind) -> Color {
        switch type {
        case .same: .clear
        case .added: .green.opacity(0.15)
        case .removed: .red.opacity(0.15)
        }
    }
}
