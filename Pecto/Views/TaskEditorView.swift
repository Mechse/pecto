import SwiftUI
import PectoKit

struct TaskEditorView: View {
    @Bindable var model: AppModel
    @Binding var detailPath: [DetailRoute]
    @AppStorage("historyPaneOpen") private var isHistoryOpen = false

    var body: some View {
        if let task = model.selectedTask {
            editor(for: task)
        } else {
            ContentUnavailableView(
                "Pick a task",
                systemImage: "sidebar.left",
                description: Text("Select a task on the left, or create a new one.")
            )
        }
    }

    private func editor(for task: TaskSummary) -> some View {
        VStack(spacing: 0) {
            if let problem = model.draftValidationError {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.yellow.opacity(0.15))
            }

            TextEditor(text: $model.draft)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
        }
        .navigationTitle(task.name ?? task.path)
        .navigationSubtitle(model.isDirty ? "Edited" : "")
        .inspector(isPresented: $isHistoryOpen) {
            HistoryPanel(model: model, task: task)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 460)
        }
        .toolbar {
            ToolbarItemGroup {
                if model.runner.runningPaths.contains(task.path) {
                    ProgressView()
                        .controlSize(.small)
                        .help("Running…")
                } else {
                    Button {
                        model.runSelectedTask()
                    } label: {
                        Label("Run", systemImage: "play.fill")
                    }
                    .keyboardShortcut("r")
                    .disabled(model.draftRunProblem != nil)
                    .help(model.draftRunProblem ?? "Save and run this task on your clipboard (⌘R)")
                }

                Button("Save") { model.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.isDirty)

                Toggle(isOn: $isHistoryOpen) {
                    Label("History", systemImage: "clock.arrow.circlepath")
                }
                .help("Show run and change history")

                Button {
                    detailPath.append(.config)
                } label: {
                    Label("Configure", systemImage: "gearshape")
                }
                .help("Name, description, shortcut, model and deletion for this task")
            }
        }
    }
}
