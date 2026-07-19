import SwiftUI
import PectoKit

struct TaskEditorView: View {
    @Bindable var model: AppModel
    @State private var isRenaming = false
    @State private var renameTo = ""
    @State private var isConfirmingDelete = false

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
        .toolbar {
            ToolbarItemGroup {
                SlotPickerView(model: model, task: task)

                Button("Save") { model.save() }
                    .keyboardShortcut("s")
                    .disabled(!model.isDirty)

                Menu {
                    Button("Rename…") {
                        renameTo = String(task.path.dropLast(3))
                        isRenaming = true
                    }
                    Button("Delete…", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Rename task file", isPresented: $isRenaming) {
            TextField("task-name", text: $renameTo)
            Button("Rename") { model.renameSelectedTask(to: renameTo) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Renames the file only — the name: inside the task stays as written.")
        }
        .confirmationDialog(
            "Delete \(task.path)?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete Permanently", role: .destructive) { model.deleteSelectedTask() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the file and clears its shortcut.")
        }
    }
}
