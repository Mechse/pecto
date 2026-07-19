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
    private(set) var history: HistoryStore?
    /// Bumped on every history write so the pane recomputes its lists.
    private(set) var historyVersion = 0

    private(set) var tasks: [TaskSummary] = []
    private(set) var selectedPath: String?
    var draft: String = ""
    private(set) var savedContent: String = ""
    /// One-shot message for failed file operations, shown as an alert.
    var operationError: String?
    /// Whether a key is in the keychain — drives the "add your key" banner.
    private(set) var hasAPIKey = false

    init() {
        let settings = SettingsStore()
        self.settings = settings
        self.runner = RunCoordinator(settings: settings)
        openHistoryStore()
        refreshAPIKeyStatus()
        refresh()

        runner.onHistoryChanged = { [weak self] in
            self?.historyVersion += 1
        }
        let runner = self.runner
        let hotkeys = HotkeyManager { slot in
            runner.fire(slot: slot)
        }
        hotkeys.register()
        self.hotkeys = hotkeys
    }

    func refreshAPIKeyStatus() {
        hasAPIKey = KeychainService.loadAPIKey() != nil
    }

    // MARK: - History

    private func openHistoryStore() {
        let path = settings.workspaceURL
            .appendingPathComponent(".pecto/pecto.db").path
        history = try? HistoryStore(path: path)
        runner.history = history
    }

    func runs(for path: String) -> [RunRecord] {
        _ = historyVersion
        return history?.listRuns(taskPath: path) ?? []
    }

    func snapshots(for path: String) -> [SnapshotRecord] {
        _ = historyVersion
        return history?.listSnapshots(taskPath: path) ?? []
    }

    func snapshotDetail(id: Int) -> (record: SnapshotRecord, content: String, prevContent: String)? {
        _ = historyVersion
        return history?.getSnapshot(id: id)
    }

    func restoreSnapshot(id: Int) {
        guard let selectedPath, let detail = history?.getSnapshot(id: id) else { return }
        run {
            try settings.workspace.writeFile(selectedPath, content: detail.content)
            recordSnapshot(kind: .restored, path: selectedPath, content: detail.content)
            draft = detail.content
            savedContent = detail.content
            refresh()
        }
    }

    private func recordSnapshot(kind: SnapshotKind, path: String, content: String) {
        history?.recordSnapshot(taskPath: path, kind: kind, content: content, at: Self.nowMilliseconds())
        historyVersion += 1
    }

    private static func nowMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
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

    /// Why the draft can't run right now (parse problem or a non-clipboard
    /// placeholder) — nil when it's runnable. Judged on the draft because the
    /// Run button saves it before running.
    var draftRunProblem: String? {
        guard selectedPath != nil else { return nil }
        let task: ParsedTask
        do {
            task = try parseTask(draft)
        } catch let error as TaskParseError {
            return error.message
        } catch {
            return "This task could not be read."
        }
        if case .notRunnable(let reason) = slotRunnability(instructions: task.instructions) {
            return reason
        }
        return nil
    }

    /// The editor's Run button: persist what's on screen, then run it through
    /// the same pipeline as a shortcut (clipboard in → clipboard out).
    func runSelectedTask() {
        guard let selectedPath, draftRunProblem == nil else { return }
        save()
        runner.run(path: selectedPath)
    }

    func save() {
        guard let selectedPath, isDirty else { return }
        run {
            try settings.workspace.writeFile(selectedPath, content: draft)
            recordSnapshot(kind: .edited, path: selectedPath, content: draft)
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
            let content = try settings.workspace.createTask(path)
            recordSnapshot(kind: .created, path: path, content: content)
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
            history?.renameTask(from: selectedPath, to: newPath, content: savedContent, at: Self.nowMilliseconds())
            historyVersion += 1
            refresh()
            select(newPath)
        }
    }

    func deleteSelectedTask() {
        guard let selectedPath else { return }
        run {
            try settings.workspace.deleteTask(selectedPath)
            settings.handleTaskDeleted(selectedPath)
            history?.deleteTask(taskPath: selectedPath)
            historyVersion += 1
            select(nil)
            refresh()
        }
    }

    func changeWorkspace(to path: String) {
        settings.setWorkspacePath(path)
        openHistoryStore()
        historyVersion += 1
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
