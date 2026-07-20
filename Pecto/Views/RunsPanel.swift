import SwiftUI
import PectoKit

/// Bottom pane: the selected task's run history — compact list on the left,
/// the selected run's full text on the right.
struct RunsPanel: View {
    enum RunSection: String, CaseIterable {
        case output = "Output"
        case input = "Input"
        case error = "Error"
    }

    let model: AppModel
    let task: TaskSummary
    @State private var selectedRunID: String?
    @State private var section: RunSection = .output

    var body: some View {
        let runs = model.runs(for: task.path)
        if runs.isEmpty {
            ContentUnavailableView(
                "No runs yet",
                systemImage: "play.slash",
                description: Text("Trigger this task with its shortcut and the run will show up here.")
            )
        } else {
            let selected = runs.first { $0.id == selectedRunID } ?? runs[0]
            HStack(spacing: 0) {
                List(runs, selection: $selectedRunID) { run in
                    RunRow(run: run)
                }
                .listStyle(.inset)
                .frame(width: 250)

                Divider()

                detailPane(for: selected)
            }
            .onAppear {
                selectedRunID = runs[0].id
                section = defaultSection(for: runs[0])
            }
            .onChange(of: selected.id) {
                section = defaultSection(for: selected)
            }
        }
    }

    // MARK: - Detail pane

    private func detailPane(for run: RunRecord) -> some View {
        let available = sections(for: run)
        let current = available.contains(section) ? section : defaultSection(for: run)
        return VStack(spacing: 0) {
            HStack(spacing: 8) {
                if available.count > 1 {
                    Picker("Section", selection: $section) {
                        ForEach(available, id: \.self) { section in
                            Text(section.rawValue).tag(section)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }

                Spacer()

                Text(tokensLine(for: run))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(text(for: current, in: run) ?? "", forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy \(current.rawValue.lowercased()) to the clipboard")
            }
            .padding(8)

            Divider()

            ScrollView {
                Text(text(for: current, in: run) ?? "—")
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func sections(for run: RunRecord) -> [RunSection] {
        var available: [RunSection] = []
        if let output = run.output, !output.isEmpty { available.append(.output) }
        if run.inputs?["clipboard"] != nil { available.append(.input) }
        if run.error != nil { available.append(.error) }
        return available
    }

    private func defaultSection(for run: RunRecord) -> RunSection {
        if let output = run.output, !output.isEmpty { return .output }
        if run.error != nil { return .error }
        return .input
    }

    private func text(for section: RunSection, in run: RunRecord) -> String? {
        switch section {
        case .output: run.output
        case .input: run.inputs?["clipboard"]
        case .error: run.error
        }
    }

    private func tokensLine(for run: RunRecord) -> String {
        var parts = [run.model]
        if let input = run.inputTokens, let output = run.outputTokens {
            parts.append("\(input) in → \(output) out")
        }
        return parts.joined(separator: "  ·  ")
    }
}

// MARK: - Run row

private struct RunRow: View {
    let run: RunRecord

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: run.status == .succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(run.status == .succeeded ? .green : .red)
            Text(
                Date(timeIntervalSince1970: Double(run.startedAt) / 1000),
                format: .dateTime.month(.abbreviated).day().hour().minute()
            )
            Spacer()
            Text(duration)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var duration: String {
        String(format: "%.1fs", Double(run.finishedAt - run.startedAt) / 1000)
    }
}
