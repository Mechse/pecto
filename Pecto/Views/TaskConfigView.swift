import SwiftUI
import PectoKit

/// Per-task configuration, pushed onto the detail column from the editor.
/// Edits commit immediately (on submit / focus loss) — there is no separate
/// save step, and unsaved editor text is never touched by config writes.
struct TaskConfigView: View {
    @Bindable var model: AppModel
    @State private var name = ""
    @State private var descriptionText = ""
    @State private var isConfirmingDelete = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case name, description
    }

    var body: some View {
        if let task = model.selectedTask, model.document != nil {
            form(for: task)
        } else {
            ContentUnavailableView(
                "No task selected",
                systemImage: "gearshape",
                description: Text("Go back and pick a task to configure.")
            )
        }
    }

    private func form(for task: TaskSummary) -> some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .focused($focusedField, equals: .name)
                    .onSubmit(commitName)
            } footer: {
                Text("Lowercase letters, numbers and dashes. Changing it renames the task's file.")
            }

            Section {
                TextField("Description", text: $descriptionText, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focusedField, equals: .description)
                    .onSubmit(commitDescription)
            } footer: {
                Text("One line about what this task does. It is sent to the model with every run.")
            }

            Section {
                SlotPickerView(model: model, task: task)
            } footer: {
                Text("A global shortcut that runs this task on your clipboard from anywhere.")
            }

            Section {
                Picker("Model", selection: modelBinding) {
                    Text("Default (\(AnthropicClient.defaultModel))").tag(nil as String?)
                    ForEach(modelChoices, id: \.self) { id in
                        Text(id).tag(Optional(id))
                    }
                }
            } footer: {
                Text("Which Claude model runs this task.")
            }

            Section {
                Button("Delete Task…", role: .destructive) {
                    isConfirmingDelete = true
                }
            } footer: {
                Text("Permanently deletes the file and clears its shortcut.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Configure")
        .navigationSubtitle(task.name ?? task.path)
        .confirmationDialog(
            "Delete \(task.path)?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete Permanently", role: .destructive) { model.deleteSelectedTask() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the file and clears its shortcut.")
        }
        .onAppear(perform: reload)
        .onChange(of: model.selectedPath) { reload() }
        .onChange(of: focusedField) { old, _ in
            // Commit on focus loss, not just Return.
            if old == .name { commitName() }
            if old == .description { commitDescription() }
        }
        .onDisappear {
            commitName()
            commitDescription()
        }
    }

    /// The curated picker choices, plus the file's current model if it isn't
    /// one of them — opening the config must never silently reset it.
    private var modelChoices: [String] {
        var choices = AnthropicClient.selectableModels
        if let current = model.document?.frontmatter.model, !choices.contains(current) {
            choices.append(current)
        }
        return choices
    }

    private var modelBinding: Binding<String?> {
        Binding(
            get: { model.document?.frontmatter.model },
            set: { model.updateModel($0) }
        )
    }

    private func reload() {
        name = String((model.selectedPath ?? "").dropLast(3))
        descriptionText = model.document?.frontmatter.description ?? ""
    }

    private func commitName() {
        guard let selectedPath = model.selectedPath else { return }
        if name != String(selectedPath.dropLast(3)) {
            model.renameSelectedTask(to: name)
        }
        // Reflect the outcome — slugified on success, reverted on failure.
        name = String((model.selectedPath ?? "").dropLast(3))
    }

    private func commitDescription() {
        model.updateDescription(descriptionText)
        descriptionText = model.document?.frontmatter.description ?? ""
    }
}
