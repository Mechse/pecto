import SwiftUI
import PectoKit

struct TaskEditorView: View {
    @Bindable var model: AppModel
    @Binding var detailPath: [DetailRoute]
    @AppStorage("historyPaneOpen") private var isChangesOpen = false
    @AppStorage("runsPaneOpen") private var isRunsOpen = false
    @AppStorage("runsPaneHeight") private var runsPaneHeight = 240.0
    @AppStorage(EditorFont.sizeKey) private var fontSize = EditorFont.defaultSize
    @State private var dragBaseHeight: Double?

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
                .font(.system(size: fontSize, design: .monospaced))
                .lineSpacing(fontSize * EditorFont.lineSpacingFactor)
                .scrollContentBackground(.hidden)
                .padding(8)

            if isRunsOpen {
                splitter
                RunsPanel(model: model, task: task)
                    .id(task.path)
                    .frame(height: runsPaneHeight)
            }
        }
        .background {
            // ⌘= alias for Increase Font Size — "+" is Shift+= on most layouts.
            Button("") { fontSize = EditorFont.clamped(fontSize + 1) }
                .keyboardShortcut("=", modifiers: .command)
                .hidden()
        }
        .navigationTitle(task.name ?? task.path)
        .navigationSubtitle(model.isDirty ? "Edited" : "")
        .inspector(isPresented: $isChangesOpen) {
            ChangesPanel(model: model, task: task)
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

                Toggle(isOn: $isRunsOpen) {
                    Label("Runs", systemImage: "play.rectangle.on.rectangle")
                }
                .keyboardShortcut("y", modifiers: [.command, .shift])
                .help("Show run history below the editor (⇧⌘Y)")

                Toggle(isOn: $isChangesOpen) {
                    Label("Changes", systemImage: "plus.forwardslash.minus")
                }
                .help("Show change history for this task")

                Button {
                    detailPath.append(.config)
                } label: {
                    Label("Configure", systemImage: "gearshape")
                }
                .help("Name, description, shortcut, model and deletion for this task")
            }
        }
    }

    /// Drag handle between the editor and the runs panel; height persists via AppStorage.
    private var splitter: some View {
        Divider()
            .overlay(Rectangle().fill(.clear).frame(height: 8).contentShape(.rect))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = dragBaseHeight ?? runsPaneHeight
                        dragBaseHeight = base
                        runsPaneHeight = min(600, max(120, base - value.translation.height))
                    }
                    .onEnded { _ in dragBaseHeight = nil }
            )
            .onHover { inside in
                if inside {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
    }
}
