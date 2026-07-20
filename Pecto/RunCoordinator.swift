import Foundation
import Observation
import PectoKit

/// The most recent run feedback, mirrored into the main window so the app
/// never depends on notifications alone (dev builds may not be able to
/// register with Notification Center).
struct RunOutcome: Equatable {
    enum Kind {
        case success, failure, refusal
    }

    let taskPath: String
    let kind: Kind
    let message: String
    let at: Date
}

/// A run that stopped pre-flight because the task wants the clipboard but it
/// was empty. Held until the user confirms (re-trigger or notch button),
/// cancels, or the timeout clears it.
struct PendingConfirmation: Equatable {
    let taskPath: String
    let taskName: String
    let requestedAt: Date
}

/// Executes a shortcut-slot run: clipboard in → model → clipboard out.
/// Failures and refusals are reported loudly (notification + window status
/// bar); success is deliberately quiet — just the brief notch flash — since
/// "it worked, paste away" is the expected outcome, not news.
/// The clipboard is only touched on success.
@MainActor
@Observable
final class RunCoordinator {
    private let settings: SettingsStore
    private let providers: ProviderRegistry

    /// Injected by AppModel; swapped when the workspace changes.
    var history: HistoryStore?
    var onHistoryChanged: (() -> Void)?

    private(set) var runningPaths: Set<String> = []
    private(set) var lastOutcome: RunOutcome?
    private(set) var pendingConfirmation: PendingConfirmation?
    private var pendingExpiryTask: Task<Void, Never>?
    private static let confirmationTimeout: Duration = .seconds(8)

    var isRunning: Bool { !runningPaths.isEmpty }

    func clearOutcome() {
        lastOutcome = nil
    }

    /// Failures and refusals go to both channels: a notification (for
    /// background runs) and the in-window status bar (always visible).
    /// Success only records `lastOutcome` for the notch's short-lived flash —
    /// no notification, and the status bar skips success outcomes.
    private func report(path: String, kind: RunOutcome.Kind, title: String, body: String) {
        lastOutcome = RunOutcome(taskPath: path, kind: kind, message: "\(title) — \(body)", at: Date())
        if kind != .success {
            NotificationService.post(title: title, body: body)
        }
    }

    init(settings: SettingsStore, providers: ProviderRegistry) {
        self.settings = settings
        self.providers = providers
    }

    func fire(slot: Int) {
        guard let path = settings.assignment(for: slot) else {
            report(
                path: "",
                kind: .refusal,
                title: "Nothing on ⌃⌥\(slot)",
                body: "That shortcut has no task yet. Open Pecto to assign one."
            )
            return
        }
        run(path: path)
    }

    /// Shared by shortcut slots and the editor's Run button. Re-triggering
    /// the task that is awaiting an empty-clipboard confirmation IS the
    /// confirmation; triggering any other task cancels the pending one.
    func run(path: String) {
        let confirmed = pendingConfirmation?.taskPath == path
        clearPending()
        run(path: path, allowEmptyClipboard: confirmed)
    }

    /// Confirms the pending run from the notch's button. Re-reads the
    /// clipboard: whatever is on it now is used, even if still empty.
    func confirmPending() {
        guard let pending = pendingConfirmation else { return }
        clearPending()
        run(path: pending.taskPath, allowEmptyClipboard: true)
    }

    func cancelPending() {
        clearPending()
    }

    private func clearPending() {
        pendingExpiryTask?.cancel()
        pendingExpiryTask = nil
        pendingConfirmation = nil
    }

    private func beginPendingConfirmation(path: String, name: String) {
        pendingExpiryTask?.cancel()
        pendingConfirmation = PendingConfirmation(taskPath: path, taskName: name, requestedAt: Date())
        pendingExpiryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.confirmationTimeout)
            guard !Task.isCancelled else { return }
            self?.clearPending()
        }
    }

    private func run(path: String, allowEmptyClipboard: Bool) {
        // Ignore re-triggers of a task that is already running (key repeat,
        // impatient fingers). Other tasks may run in parallel.
        guard !runningPaths.contains(path) else { return }

        let task: ParsedTask
        do {
            task = try settings.workspace.loadTask(path)
        } catch let error as TaskParseError {
            report(path: path, kind: .refusal, title: "\(path) can't run", body: error.message)
            return
        } catch {
            report(
                path: path,
                kind: .refusal,
                title: "\(path) can't run",
                body: "That slot's task could not be read. Reassign it in Pecto."
            )
            return
        }

        let name = task.frontmatter.name
        var values: [String: String] = [:]
        switch slotRunnability(instructions: task.instructions) {
        case .notRunnable(let reason):
            report(path: path, kind: .refusal, title: "\(name) can't run from a shortcut", body: reason)
            return
        case .runnable(let needsClipboard):
            if needsClipboard {
                let clipboard = ClipboardService.readText() ?? ""
                let isEmpty = clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if isEmpty && !allowEmptyClipboard {
                    // With the notch indicator on, warn there and wait for a
                    // confirmation instead of refusing outright. Without it
                    // there is no surface to confirm from, so keep the refusal.
                    guard settings.showRunningIndicator else {
                        report(
                            path: path,
                            kind: .refusal,
                            title: "\(name) needs your clipboard",
                            body: "Copy some text first, then press the shortcut again."
                        )
                        return
                    }
                    beginPendingConfirmation(path: path, name: name)
                    return
                }
                values["clipboard"] = clipboard
            }
        }

        let prompt = buildPrompt(
            task: task.frontmatter,
            filledInstructions: fillPlaceholders(task.instructions, values: values)
        )
        let ref = ModelRef.parse(
            task.frontmatter.model ?? settings.defaultModel ?? ProviderCatalog.defaultModelRef.qualified
        )
        let info = ProviderCatalog.info(for: ref.provider)
        guard let client = providers.client(for: ref.provider) else {
            report(
                path: path,
                kind: .refusal,
                title: "\(name) can't run",
                body: "\(info.displayName) isn't available on this Mac."
            )
            return
        }

        let startedAt = Self.nowMilliseconds()
        runningPaths.insert(path)
        Task {
            // The keychain read happens off the main actor: it can block on
            // a permission prompt (fresh dev signatures re-ask), and that
            // must not freeze the app mid-run.
            let apiKey: String?
            if info.requiresAPIKey {
                let provider = ref.provider
                guard let key = await Task.detached(operation: { KeychainService.loadAPIKey(for: provider) }).value else {
                    report(
                        path: path,
                        kind: .refusal,
                        title: "\(name) can't run yet",
                        body: "Add your \(info.displayName) API key in Pecto's Settings first."
                    )
                    runningPaths.remove(path)
                    return
                }
                apiKey = key
            } else {
                apiKey = nil
            }
            do {
                let output = try await client.run(prompt: prompt, apiKey: apiKey, model: ref.model)
                record(path: path, startedAt: startedAt, status: .succeeded, model: ref.qualified, output: output.text, error: nil, usage: output.usage, inputs: values)
                if output.text.isEmpty {
                    report(
                        path: path,
                        kind: .refusal,
                        title: "\(name) came back empty",
                        body: "The model returned nothing. Your clipboard is unchanged."
                    )
                } else {
                    ClipboardService.writeText(output.text)
                    report(
                        path: path,
                        kind: .success,
                        title: "\(name) finished",
                        body: "The result is on your clipboard — paste away."
                    )
                }
            } catch {
                let reason = (error as? RunError)?.message ?? error.localizedDescription
                record(path: path, startedAt: startedAt, status: .failed, model: ref.qualified, output: nil, error: reason, usage: nil, inputs: values)
                report(
                    path: path,
                    kind: .failure,
                    title: "\(name) didn't finish",
                    body: "\(reason) Your clipboard is unchanged."
                )
            }
            runningPaths.remove(path)
        }
    }

    /// Only runs that actually reached the API are recorded — pre-flight
    /// refusals (missing key, empty clipboard, unrunnable task) are not runs.
    private func record(
        path: String,
        startedAt: Int,
        status: RunStatus,
        model: String,
        output: String?,
        error: String?,
        usage: RunUsage?,
        inputs: [String: String]
    ) {
        history?.recordRun(RunRecord(
            id: UUID().uuidString,
            taskPath: path,
            startedAt: startedAt,
            finishedAt: Self.nowMilliseconds(),
            status: status,
            model: model,
            inputTokens: usage?.inputTokens,
            outputTokens: usage?.outputTokens,
            output: output,
            error: error,
            inputs: inputs.isEmpty ? nil : inputs
        ))
        onHistoryChanged?()
    }

    private static func nowMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
    }
}
