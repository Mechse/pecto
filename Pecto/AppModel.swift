import Foundation
import Observation
import PectoKit

/// Sections of the in-window Settings screen.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case apiKeys
    case workspace

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .apiKeys: "API Keys"
        case .workspace: "Workspace"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .apiKeys: "key.fill"
        case .workspace: "folder"
        }
    }
}

/// What fills the main window: the task UI, or the full-window Settings.
enum MainRoute: Equatable {
    case tasks
    case settings(SettingsSection)
}

/// Root object owning settings, the run pipeline, hotkeys, and editor state.
@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let runner: RunCoordinator
    private var hotkeys: HotkeyManager?
    private var indicator: NotchIndicatorController?
    private(set) var history: HistoryStore?
    /// Bumped on every history write so the pane recomputes its lists.
    private(set) var historyVersion = 0

    private(set) var tasks: [TaskSummary] = []
    private(set) var selectedPath: String?
    /// The selected task's settings + last-saved body. The editor never shows
    /// the frontmatter; it is round-tripped through this document on save.
    private(set) var document: TaskDocument?
    /// Body-only editor text — what the TextEditor binds to.
    var draft: String = ""
    private(set) var savedBody: String = ""
    /// The file on disk had broken settings and was repaired in memory; the
    /// repaired frontmatter must reach disk on the next write even if the
    /// body is untouched.
    private var needsRepairWrite = false
    /// One-shot message for failed file operations, shown as an alert.
    var operationError: String?
    /// What this Mac can run with — keys in the keychain plus the on-device
    /// model. Shared with the run pipeline.
    let availability: ModelAvailability
    /// The main window's content — tasks, or the full-window Settings.
    var mainRoute: MainRoute = .tasks

    /// All clients, shared by the run pipeline and the Settings Test buttons.
    let providers = ProviderRegistry(clients: [
        AnthropicClient(),
        OpenAICompatibleClient.openAI(),
        OpenAICompatibleClient.xAI(),
        GeminiClient(),
        AppleOnDeviceClient(),
    ])

    init() {
        let settings = SettingsStore()
        let availability = ModelAvailability()
        self.settings = settings
        self.availability = availability
        self.runner = RunCoordinator(
            settings: settings,
            providers: providers,
            availability: availability
        )
        openHistoryStore()
        refresh()

        runner.onHistoryChanged = { [weak self] in
            self?.historyVersion += 1
        }
        let runner = self.runner
        let hotkeys = HotkeyManager { shortcut in
            guard let path = settings.taskPath(for: shortcut) else { return }
            runner.run(path: path)
        }
        hotkeys.sync(Set(settings.shortcuts.values))
        self.hotkeys = hotkeys

        indicator = NotchIndicatorController(
            runner: runner,
            settings: settings,
            nameForPath: { [weak self] path in
                self?.tasks.first { $0.path == path }?.name ?? path
            }
        )
    }

    // Forwarded from `availability` so views keep one entry point.

    var appleAvailability: AppleModelAvailability { availability.apple }

    /// Providers with a key in the keychain — drives the missing-key banner
    /// and the status dots in Settings.
    var storedKeyProviders: Set<ProviderID> { availability.storedKeyProviders }

    /// Re-scans the keychain after a key is saved or removed.
    func refreshAPIKeyStatus() {
        availability.refresh()
    }

    // MARK: - Shortcuts

    /// What the recorder must tell the user after a keystroke is committed.
    enum ShortcutAssignmentResult: Equatable {
        case assigned
        /// The shortcut was taken over from another task.
        case replaced(taskName: String)
        /// macOS or another app owns the combo; nothing changed.
        case unavailable
    }

    @discardableResult
    func setShortcut(_ shortcut: Shortcut, for path: String) -> ShortcutAssignmentResult {
        let previousOwner = settings.taskPath(for: shortcut).flatMap { $0 == path ? nil : $0 }
        let previousOwnShortcut = settings.shortcut(for: path)

        settings.setShortcut(shortcut, for: path)
        let failed = hotkeys?.sync(Set(settings.shortcuts.values)) ?? []
        guard !failed.contains(shortcut) else {
            // Roll back: the OS refused, so the old state is still the truth.
            if let previousOwner {
                settings.setShortcut(shortcut, for: previousOwner)
            } else {
                settings.clearShortcut(for: path)
            }
            if let previousOwnShortcut {
                settings.setShortcut(previousOwnShortcut, for: path)
            }
            hotkeys?.sync(Set(settings.shortcuts.values))
            return .unavailable
        }

        if let previousOwner {
            return .replaced(taskName: String(previousOwner.dropLast(3)))
        }
        return .assigned
    }

    func clearShortcut(for path: String) {
        settings.clearShortcut(for: path)
        hotkeys?.sync(Set(settings.shortcuts.values))
    }

    /// Releases the global hotkeys while the recorder captures keystrokes, so
    /// an existing Pecto shortcut can be re-recorded without firing a run.
    func suspendHotkeys() {
        hotkeys?.suspend()
    }

    func resumeHotkeys() {
        hotkeys?.resume()
    }

    private func syncHotkeys() {
        hotkeys?.sync(Set(settings.shortcuts.values))
    }

    // MARK: - Routing

    func openSettings(_ section: SettingsSection = .general) {
        mainRoute = .settings(section)
    }

    func closeSettings() {
        mainRoute = .tasks
    }

    // MARK: - Model resolution

    /// The model a task would actually run with: its own `model:`, else the
    /// global default, else whatever this Mac can do. Nil when it can't do
    /// anything — no key stored and no on-device model.
    func resolvedModelRef(forTaskModel raw: String?) -> ModelRef? {
        if let raw { return ModelRef.parse(raw) }
        if let stored = settings.defaultModel { return ModelRef.parse(stored) }
        return availability.resolvedDefault
    }

    /// Why tasks can't run right now on the provider side — nothing set up at
    /// all, a missing key, or an unavailable on-device model. Nil when it's
    /// good to go. Judged against the selected task when there is one, so a
    /// task that overrides the model warns about *its* provider.
    var modelWarning: String? {
        guard let ref = resolvedModelRef(forTaskModel: document?.frontmatter.model) else {
            return "No model is set up yet — add an API key, or turn on Apple Intelligence, to run tasks."
        }
        let info = ProviderCatalog.info(for: ref.provider)
        if info.requiresAPIKey {
            guard !storedKeyProviders.contains(ref.provider) else { return nil }
            return "Add your \(info.displayName) API key to run this task."
        }
        return appleAvailability.explanation.map { "This task uses the Apple on-device model. \($0)" }
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
            loadDocument(from: detail.content, path: selectedPath)
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
            document = nil
            draft = ""
            savedBody = ""
            needsRepairWrite = false
            return
        }
        loadDocument(from: content, path: path)
    }

    /// Lenient load: broken settings are silently repaired in memory (name
    /// from the filename, placeholder description) — the user never sees YAML.
    private func loadDocument(from content: String, path: String) {
        let (loaded, wasRepaired) = loadDocumentRepairing(
            content, fallbackName: String(path.dropLast(3))
        )
        document = loaded
        draft = loaded.body
        savedBody = loaded.body
        needsRepairWrite = wasRepaired
    }

    // MARK: - Editing

    var isDirty: Bool {
        selectedPath != nil && draft != savedBody
    }

    /// Live problem with the unsaved draft, for the editor banner. The body is
    /// free text now — the only invalid state is having none.
    var draftValidationError: String? {
        guard selectedPath != nil else { return nil }
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "This task has no instructions yet. Describe in plain language what should happen when it runs."
        }
        return nil
    }

    /// Why the draft can't run right now (empty body or a non-clipboard
    /// placeholder) — nil when it's runnable. Judged on the draft because the
    /// Run button saves it before running.
    var draftRunProblem: String? {
        guard selectedPath != nil else { return nil }
        if let error = draftValidationError {
            return error
        }
        if case .notRunnable(let reason) = slotRunnability(instructions: draft) {
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
        guard let selectedPath, var document, isDirty || needsRepairWrite else { return }
        document.body = draft
        let content = document.serialize()
        run {
            try settings.workspace.writeFile(selectedPath, content: content)
            recordSnapshot(kind: .edited, path: selectedPath, content: content)
            self.document = document
            savedBody = draft
            needsRepairWrite = false
            refresh()
        }
    }

    // MARK: - Task config

    /// Config edits write through immediately, serialized with the *saved*
    /// body — they never commit (or lose) unsaved editor text.
    private func updateFrontmatter(_ mutate: (inout TaskFrontmatter) -> Void) {
        guard let selectedPath, var document else { return }
        mutate(&document.frontmatter)
        document.body = savedBody
        let content = document.serialize()
        run {
            try settings.workspace.writeFile(selectedPath, content: content)
            recordSnapshot(kind: .edited, path: selectedPath, content: content)
            self.document = document
            needsRepairWrite = false
            refresh()
        }
    }

    func updateDescription(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != document?.frontmatter.description else { return }
        updateFrontmatter { $0.description = trimmed }
    }

    func updateModel(_ model: String?) {
        guard model != document?.frontmatter.model else { return }
        updateFrontmatter { $0.model = model }
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

    /// Renames the file AND rewrites the frontmatter `name:` to match — the
    /// config view's Name field is the single rename surface. Unsaved body
    /// edits survive: the write uses `savedBody` and the draft is kept.
    func renameSelectedTask(to input: String) {
        guard let selectedPath, var document else { return }
        let slug = Self.slugify(input)
        guard !slug.isEmpty else {
            operationError = "Task names use lowercase letters, numbers and dashes (e.g. enrich-new-signups)."
            return
        }
        let newPath = "\(slug).md"
        guard newPath != selectedPath || document.frontmatter.name != slug else { return }
        document.frontmatter.name = slug
        document.body = savedBody
        let content = document.serialize()
        run {
            if newPath != selectedPath {
                try settings.workspace.renameTask(from: selectedPath, to: newPath)
                try settings.workspace.writeFile(newPath, content: content)
                settings.handleTaskRenamed(from: selectedPath, to: newPath)
                history?.renameTask(from: selectedPath, to: newPath, content: content, at: Self.nowMilliseconds())
                historyVersion += 1
            } else {
                try settings.workspace.writeFile(newPath, content: content)
                recordSnapshot(kind: .edited, path: newPath, content: content)
            }
            self.document = document
            needsRepairWrite = false
            self.selectedPath = newPath
            refresh()
        }
    }

    func deleteSelectedTask() {
        guard let selectedPath else { return }
        run {
            try settings.workspace.deleteTask(selectedPath)
            settings.handleTaskDeleted(selectedPath)
            syncHotkeys()
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
