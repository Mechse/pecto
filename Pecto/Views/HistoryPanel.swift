import SwiftUI
import PectoKit

/// Right-hand pane: the selected task's run history and change history.
struct HistoryPanel: View {
    enum Tab: String, CaseIterable {
        case runs = "Runs"
        case changes = "Changes"
    }

    let model: AppModel
    let task: TaskSummary
    @State private var tab: Tab = .runs

    var body: some View {
        VStack(spacing: 0) {
            Picker("History", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            switch tab {
            case .runs: runsList
            case .changes: changesList
            }
        }
    }

    // MARK: - Runs

    private var runsList: some View {
        let runs = model.runs(for: task.path)
        return Group {
            if runs.isEmpty {
                emptyState("No runs yet", "Trigger this task with its shortcut and the run will show up here.")
            } else {
                List(runs) { run in
                    RunEntry(run: run)
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Changes

    private var changesList: some View {
        let snapshots = model.snapshots(for: task.path)
        return Group {
            if snapshots.isEmpty {
                emptyState("No changes yet", "Save the task and each version will show up here.")
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

    private func emptyState(_ title: String, _ detail: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: "clock.arrow.circlepath",
            description: Text(detail)
        )
    }
}

private func timestamp(_ milliseconds: Int) -> Text {
    Text(
        Date(timeIntervalSince1970: Double(milliseconds) / 1000),
        format: .dateTime.month(.abbreviated).day().hour().minute()
    )
}

// MARK: - Run entry

private struct RunEntry: View {
    let run: RunRecord
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let clipboard = run.inputs?["clipboard"] {
                    detailSection("Clipboard input", clipboard)
                }
                if let output = run.output, !output.isEmpty {
                    detailSection("Output", output)
                }
                if let error = run.error {
                    detailSection("Error", error)
                }
            }
            .padding(.vertical, 4)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: run.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(run.status == .succeeded ? .green : .red)
                    timestamp(run.startedAt)
                    Spacer()
                    Text(duration)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(tokensLine)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var duration: String {
        String(format: "%.1fs", Double(run.finishedAt - run.startedAt) / 1000)
    }

    private var tokensLine: String {
        var parts = [run.model]
        if let input = run.inputTokens, let output = run.outputTokens {
            parts.append("\(input) in → \(output) out")
        }
        return parts.joined(separator: "  ·  ")
    }

    private func detailSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
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
