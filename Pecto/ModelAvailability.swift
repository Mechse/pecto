import Foundation
import Observation
import PectoKit

/// What this Mac can actually run tasks with: which providers have a key in
/// the keychain, and whether the on-device model is usable. Shared by the UI
/// (banner, status dots, picker labels) and the run pipeline, which is why it
/// lives outside AppModel — RunCoordinator needs it too.
@MainActor
@Observable
final class ModelAvailability {
    /// Checked once at launch; drives the Apple rows in pickers and Settings.
    let apple = AppleModelAvailability.check()

    /// Providers with a key in the keychain. Empty until the first scan
    /// finishes — use `resolvedDefaultAwaitingKeys()` when that matters.
    private(set) var storedKeyProviders: Set<ProviderID> = []

    @ObservationIgnored
    private var loadTask: Task<Set<ProviderID>, Never>?
    /// Bumped per scan so a slow earlier scan can't overwrite a newer result
    /// (Save Key then Remove Key in quick succession).
    @ObservationIgnored
    private var loadGeneration = 0

    init() {
        refresh()
    }

    /// Off the main actor: reading the keychain can block on a permission
    /// prompt (every fresh dev signature re-asks), and this runs during
    /// launch — a synchronous read would freeze the app before the menu bar
    /// icon or hotkeys exist.
    func refresh() {
        let scan = Task.detached(priority: .utility) {
            Set(
                ProviderCatalog.all
                    .filter(\.requiresAPIKey)
                    .map(\.id)
                    .filter { KeychainService.loadAPIKey(for: $0) != nil }
            )
        }
        loadTask = scan
        loadGeneration += 1
        let generation = loadGeneration
        Task { [weak self] in
            let stored = await scan.value
            guard let self, generation == loadGeneration else { return }
            storedKeyProviders = stored
        }
    }

    /// The automatic default, from whatever is known right now. For UI, where
    /// an observation-driven redraw picks up the scan when it lands.
    var resolvedDefault: ModelRef? {
        DefaultModelResolution.resolve(
            storedKeyProviders: storedKeyProviders,
            appleAvailable: apple.isAvailable
        )
    }

    /// The automatic default, waiting for an in-flight keychain scan first —
    /// so a hotkey pressed during launch doesn't get told "no model set up"
    /// merely because the scan hadn't finished.
    func resolvedDefaultAwaitingKeys() async -> ModelRef? {
        if let loadTask {
            let stored = await loadTask.value
            storedKeyProviders = stored
        }
        return resolvedDefault
    }
}
