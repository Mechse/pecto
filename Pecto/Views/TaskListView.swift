import SwiftUI
import PectoKit

struct TaskListView: View {
    @Bindable var model: AppModel
    @State private var isCreating = false
    @State private var newTaskName = ""

    var body: some View {
        List(selection: selectionBinding) {
            ForEach(model.tasks) { task in
                row(for: task)
                    .tag(task.path)
            }
        }
        .navigationTitle("Tasks")
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        .overlay {
            if model.tasks.isEmpty {
                ContentUnavailableView(
                    "No tasks yet",
                    systemImage: "doc.badge.plus",
                    description: Text("Create your first task with the + button.")
                )
            }
        }
        .toolbar {
            Button {
                model.openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .help("Open Settings (⌘,)")

            Button {
                newTaskName = ""
                isCreating = true
            } label: {
                Label("New Task", systemImage: "plus")
            }
            .help("New task")
        }
        .alert("New task", isPresented: $isCreating) {
            TextField("improve-email", text: $newTaskName)
            Button("Create") { model.createTask(named: newTaskName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Names use lowercase letters, numbers and dashes.")
        }
    }

    private var selectionBinding: Binding<String?> {
        Binding(
            get: { model.selectedPath },
            set: { model.select($0) }
        )
    }

    private func row(for task: TaskSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(task.name ?? task.path)
                if task.error != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(task.error ?? "")
                }
                Spacer()
                if let shortcut = model.settings.shortcut(for: task.path) {
                    Text(shortcut.display)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Text(task.description ?? task.error ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 2)
    }
}
