import Foundation
import Observation
import PectoKit

/// Root object owning settings, the run pipeline, hotkeys, and editor state.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let runner: RunCoordinator
    private var hotkeys: HotkeyManager?

    private(set) var tasks: [TaskSummary] = []
    private(set) var selectedPath: String?
    var draft: String = ""
    private(set) var savedContent: String = ""
    /// One-shot message for failed file operations, shown as an alert.
    var operationError: String?

    init() {
        let settings = SettingsStore()
        self.settings = settings
        self.runner = RunCoordinator(settings: settings)
        refresh()

        let runner = self.runner
        let hotkeys = HotkeyManager { slot in
            runner.fire(slot: slot)
        }
        hotkeys.register()
        self.hotkeys = hotkeys
    }

    // MARK: - Task list

    func refresh() {
        tasks = (try? settings.workspace.listTasks()) ?? []
        if let selectedPath, !tasks.contains(where: { $0.path == selectedPath }) {
            select(nil)
        }
    }

    var selectedTask: TaskSummary? {
        tasks.first { $0.path == selectedPath }
    }

    func select(_ path: String?) {
        selectedPath = path
        guard let path, let content = try? settings.workspace.readFile(path) else {
            draft = ""
            savedContent = ""
            return
        }
        draft = content
        savedContent = content
    }

    // MARK: - Editing

    var isDirty: Bool {
        selectedPath != nil && draft != savedContent
    }

    /// Live parse problem of the unsaved draft, for the editor banner.
    var draftValidationError: String? {
        guard selectedPath != nil else { return nil }
        do {
            _ = try parseTask(draft)
            return nil
        } catch let error as TaskParseError {
            return error.message
        } catch {
            return nil
        }
    }

    func save() {
        guard let selectedPath, isDirty else { return }
        run {
            try settings.workspace.writeFile(selectedPath, content: draft)
            savedContent = draft
            refresh()
        }
    }

    // MARK: - Lifecycle

    func createTask(named input: String) {
        let slug = Self.slugify(input)
        guard !slug.isEmpty else {
            operationError = "Task file names use lowercase letters, numbers and dashes (e.g. enrich-new-signups)."
            return
        }
        let path = "\(slug).md"
        run {
            try settings.workspace.createTask(path)
            refresh()
            select(path)
        }
    }

    func renameSelectedTask(to input: String) {
        guard let selectedPath else { return }
        let slug = Self.slugify(input)
        let newPath = "\(slug).md"
        guard newPath != selectedPath else { return }
        run {
            try settings.workspace.renameTask(from: selectedPath, to: newPath)
            settings.handleTaskRenamed(from: selectedPath, to: newPath)
            refresh()
            select(newPath)
        }
    }

    func deleteSelectedTask() {
        guard let selectedPath else { return }
        run {
            try settings.workspace.deleteTask(selectedPath)
            settings.handleTaskDeleted(selectedPath)
            select(nil)
            refresh()
        }
    }

    func changeWorkspace(to path: String) {
        settings.setWorkspacePath(path)
        select(nil)
        refresh()
    }

    // MARK: - Helpers

    private func run(_ body: () throws -> Void) {
        do {
            try body()
        } catch let error as TaskParseError {
            operationError = error.message
        } catch {
            operationError = "Something went wrong."
        }
    }

    static func slugify(_ input: String) -> String {
        var result = ""
        var pendingDash = false
        for character in input.lowercased() {
            if character.isASCII, character.isLetter || character.isNumber {
                if pendingDash, !result.isEmpty {
                    result.append("-")
                }
                pendingDash = false
                result.append(character)
            } else {
                pendingDash = true
            }
        }
        return result
    }
}
