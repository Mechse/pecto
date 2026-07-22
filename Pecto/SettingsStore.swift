import Foundation
import Observation
import PectoKit

/// Persisted app settings: the workspace folder and the task→shortcut map.
@MainActor
@Observable
final class SettingsStore {
    private let defaults = UserDefaults.standard
    private static let workspacePathKey = "workspacePath"
    private static let shortcutsKey = "taskShortcuts"
    /// Pre-recording shortcut model (slot number → task filename); read once
    /// for migration, then deleted.
    private static let legacySlotAssignmentsKey = "slotAssignments"
    private static let didSeedWorkspaceKey = "didSeedWorkspace"
    private static let showRunningIndicatorKey = "showRunningIndicator"
    private static let defaultModelKey = "defaultModel"

    private(set) var workspacePath: String
    /// Task filename → the global shortcut that runs it.
    private(set) var shortcuts: [String: Shortcut]
    /// Whether the notch/top-of-screen pill appears while a task runs.
    private(set) var showRunningIndicator: Bool
    /// Provider-qualified model ref for tasks without their own `model:`;
    /// nil falls back to the built-in default.
    private(set) var defaultModel: String?

    init() {
        workspacePath = defaults.string(forKey: Self.workspacePathKey) ?? ""
        showRunningIndicator = defaults.object(forKey: Self.showRunningIndicatorKey) as? Bool ?? true
        defaultModel = defaults.string(forKey: Self.defaultModelKey)
        let stored = defaults.dictionary(forKey: Self.shortcutsKey) as? [String: String] ?? [:]
        shortcuts = stored.compactMapValues(Shortcut.init(rawValue:))
        migrateLegacySlotsIfNeeded()
        prepareWorkspace()
    }

    /// One-shot upgrade from the fixed ⌃⌥1–9 slots to recorded shortcuts, so
    /// existing assignments keep working with the same keystrokes.
    private func migrateLegacySlotsIfNeeded() {
        guard defaults.object(forKey: Self.shortcutsKey) == nil,
              let legacy = defaults.dictionary(forKey: Self.legacySlotAssignmentsKey) as? [String: String]
        else { return }

        for (slotKey, path) in legacy {
            guard let slot = Int(slotKey), let shortcut = Shortcut.legacySlot(slot) else { continue }
            shortcuts[path] = shortcut
        }
        persistShortcuts()
        defaults.removeObject(forKey: Self.legacySlotAssignmentsKey)
    }

    var workspaceURL: URL {
        URL(fileURLWithPath: workspacePath)
    }

    var workspace: WorkspaceStore {
        WorkspaceStore(root: workspaceURL)
    }

    // MARK: - Workspace folder

    func setWorkspacePath(_ path: String) {
        workspacePath = path
        defaults.set(path, forKey: Self.workspacePathKey)
    }

    /// Ensures a workspace exists; on the very first launch, creates
    /// ~/Documents/Pecto and seeds it with the sample tasks.
    private func prepareWorkspace() {
        if workspacePath.isEmpty {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
            setWorkspacePath(documents.appendingPathComponent("Pecto").path)
        }
        try? FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        if !defaults.bool(forKey: Self.didSeedWorkspaceKey) {
            for (fileName, content) in SampleTasks.all {
                let url = workspaceURL.appendingPathComponent(fileName)
                if !FileManager.default.fileExists(atPath: url.path) {
                    try? content.write(to: url, atomically: true, encoding: .utf8)
                }
            }
            defaults.set(true, forKey: Self.didSeedWorkspaceKey)
        }
    }

    // MARK: - Default model

    func setDefaultModel(_ ref: String?) {
        defaultModel = ref
        if let ref {
            defaults.set(ref, forKey: Self.defaultModelKey)
        } else {
            defaults.removeObject(forKey: Self.defaultModelKey)
        }
    }

    // MARK: - Running indicator

    func setShowRunningIndicator(_ enabled: Bool) {
        showRunningIndicator = enabled
        defaults.set(enabled, forKey: Self.showRunningIndicatorKey)
    }

    // MARK: - Shortcuts

    func shortcut(for path: String) -> Shortcut? {
        shortcuts[path]
    }

    func taskPath(for shortcut: Shortcut) -> String? {
        shortcuts.first(where: { $0.value == shortcut })?.key
    }

    /// Gives `shortcut` to `path`, taking it over from whichever task held it.
    func setShortcut(_ shortcut: Shortcut, for path: String) {
        for (existingPath, existing) in shortcuts where existing == shortcut && existingPath != path {
            shortcuts.removeValue(forKey: existingPath)
        }
        shortcuts[path] = shortcut
        persistShortcuts()
    }

    func clearShortcut(for path: String) {
        guard shortcuts.removeValue(forKey: path) != nil else { return }
        persistShortcuts()
    }

    func handleTaskRenamed(from: String, to: String) {
        guard let shortcut = shortcuts.removeValue(forKey: from) else { return }
        shortcuts[to] = shortcut
        persistShortcuts()
    }

    func handleTaskDeleted(_ path: String) {
        clearShortcut(for: path)
    }

    private func persistShortcuts() {
        defaults.set(shortcuts.mapValues(\.rawValue), forKey: Self.shortcutsKey)
    }
}
