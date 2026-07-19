import Foundation
import Observation
import PectoKit

/// Persisted app settings: the workspace folder and the shortcut-slot map.
@MainActor
@Observable
final class SettingsStore {
    static let slotCount = 9

    private let defaults = UserDefaults.standard
    private static let workspacePathKey = "workspacePath"
    private static let slotAssignmentsKey = "slotAssignments"
    private static let didSeedWorkspaceKey = "didSeedWorkspace"
    private static let showRunningIndicatorKey = "showRunningIndicator"

    private(set) var workspacePath: String
    /// Slot number (1–9) → task filename.
    private(set) var slotAssignments: [Int: String]
    /// Whether the notch/top-of-screen pill appears while a task runs.
    private(set) var showRunningIndicator: Bool

    init() {
        workspacePath = defaults.string(forKey: Self.workspacePathKey) ?? ""
        showRunningIndicator = defaults.object(forKey: Self.showRunningIndicatorKey) as? Bool ?? true
        let stored = defaults.dictionary(forKey: Self.slotAssignmentsKey) as? [String: String] ?? [:]
        slotAssignments = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in
            Int(key).map { ($0, value) }
        })
        prepareWorkspace()
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

    // MARK: - Running indicator

    func setShowRunningIndicator(_ enabled: Bool) {
        showRunningIndicator = enabled
        defaults.set(enabled, forKey: Self.showRunningIndicatorKey)
    }

    // MARK: - Slot assignments

    func assignment(for slot: Int) -> String? {
        slotAssignments[slot]
    }

    func slot(for path: String) -> Int? {
        slotAssignments.first(where: { $0.value == path })?.key
    }

    /// Assigns `path` to `slot` (taking the slot over from any other task);
    /// `nil` unassigns the task from all slots.
    func assign(_ path: String, to slot: Int?) {
        for (existingSlot, existingPath) in slotAssignments where existingPath == path {
            slotAssignments.removeValue(forKey: existingSlot)
        }
        if let slot {
            slotAssignments[slot] = path
        }
        persistSlots()
    }

    func handleTaskRenamed(from: String, to: String) {
        for (slot, path) in slotAssignments where path == from {
            slotAssignments[slot] = to
        }
        persistSlots()
    }

    func handleTaskDeleted(_ path: String) {
        for (slot, existing) in slotAssignments where existing == path {
            slotAssignments.removeValue(forKey: slot)
        }
        persistSlots()
    }

    private func persistSlots() {
        let stored = Dictionary(uniqueKeysWithValues: slotAssignments.map { (String($0.key), $0.value) })
        defaults.set(stored, forKey: Self.slotAssignmentsKey)
    }
}
