import Foundation
import Observation
import PectoKit

/// Executes a shortcut-slot run: clipboard in → Anthropic → clipboard out,
/// with a notification either way. The clipboard is only touched on success.
@MainActor
@Observable
final class RunCoordinator {
    private let settings: SettingsStore
    private let client = AnthropicClient()

    private(set) var runningSlots: Set<Int> = []

    var isRunning: Bool { !runningSlots.isEmpty }

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func fire(slot: Int) {
        // Ignore re-triggers of a slot that is already running (key repeat,
        // impatient fingers). Other slots may run in parallel.
        guard !runningSlots.contains(slot) else { return }

        guard let path = settings.assignment(for: slot) else {
            NotificationService.post(
                title: "Nothing on ⌃⌥\(slot)",
                body: "That shortcut has no task yet. Open Pecto to assign one."
            )
            return
        }

        let task: ParsedTask
        do {
            task = try settings.workspace.loadTask(path)
        } catch let error as TaskParseError {
            NotificationService.post(title: "\(path) can't run", body: error.message)
            return
        } catch {
            NotificationService.post(
                title: "\(path) can't run",
                body: "That slot's task could not be read. Reassign it in Pecto."
            )
            return
        }

        let name = task.frontmatter.name
        var values: [String: String] = [:]
        switch slotRunnability(instructions: task.instructions) {
        case .notRunnable(let reason):
            NotificationService.post(title: "\(name) can't run from a shortcut", body: reason)
            return
        case .runnable(let needsClipboard):
            if needsClipboard {
                let clipboard = ClipboardService.readText() ?? ""
                guard !clipboard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    NotificationService.post(
                        title: "\(name) needs your clipboard",
                        body: "Copy some text first, then press the shortcut again."
                    )
                    return
                }
                values["clipboard"] = clipboard
            }
        }

        guard let apiKey = KeychainService.loadAPIKey() else {
            NotificationService.post(
                title: "\(name) can't run yet",
                body: "Add your Anthropic API key in Pecto's Settings first."
            )
            return
        }

        let prompt = buildPrompt(
            task: task.frontmatter,
            filledInstructions: fillPlaceholders(task.instructions, values: values)
        )

        runningSlots.insert(slot)
        Task {
            do {
                let text = try await client.run(prompt: prompt, apiKey: apiKey)
                if text.isEmpty {
                    NotificationService.post(
                        title: "\(name) came back empty",
                        body: "The model returned nothing. Your clipboard is unchanged."
                    )
                } else {
                    ClipboardService.writeText(text)
                    NotificationService.post(
                        title: "\(name) finished",
                        body: "The result is on your clipboard — paste away."
                    )
                }
            } catch {
                let reason = (error as? RunError)?.message ?? error.localizedDescription
                NotificationService.post(
                    title: "\(name) didn't finish",
                    body: "\(reason) Your clipboard is unchanged."
                )
            }
            runningSlots.remove(slot)
        }
    }
}
