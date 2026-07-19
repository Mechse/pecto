import AppKit
import SwiftUI
import Observation

/// What the notch indicator is showing right now.
enum IndicatorState: Equatable {
    case hidden
    case running(primaryName: String, extraCount: Int)
    case awaitingConfirmation(name: String)
    case flash(kind: RunOutcome.Kind, message: String)
}

/// Owns the notch overlay: observes the run pipeline and drives a small
/// state machine (hidden → running → flash → running/hidden) rendered by
/// NotchIndicatorView on a click-through panel over the notch.
///
/// Reads `lastOutcome` but never clears it — the main window's status bar
/// owns `clearOutcome()`.
@MainActor
@Observable
final class NotchIndicatorController {
    private(set) var state: IndicatorState = .hidden
    private(set) var geometry = IndicatorGeometry(hasNotch: false, notchWidth: 0, topInset: 24)

    /// Room for the bar at its widest (a wing either side of the notch); the
    /// panel never resizes.
    private static let stageSize = NSSize(width: 1000, height: 140)
    private static let flashDuration: Duration = .seconds(2.5)
    /// Long enough for the shrink-away transition to finish before orderOut.
    private static let hideDelay: Duration = .milliseconds(450)

    private let runner: RunCoordinator
    private let settings: SettingsStore
    private let nameForPath: (String) -> String

    private var panel: NotchIndicatorPanel?
    /// Outcomes older than this have already been flashed (or predate launch).
    private var lastHandledOutcome: RunOutcome?
    private var isFlashing = false
    private var flashTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    init(
        runner: RunCoordinator,
        settings: SettingsStore,
        nameForPath: @escaping (String) -> String
    ) {
        self.runner = runner
        self.settings = settings
        self.nameForPath = nameForPath
        self.lastHandledOutcome = runner.lastOutcome

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screenParametersChanged()
            }
        }
        observe()
    }

    // MARK: - Observation

    /// Re-arming observation loop over the runner and settings. `sync()` is
    /// idempotent: it computes the desired state from current inputs, so
    /// racing change notifications and timer wake-ups are harmless.
    private func observe() {
        withObservationTracking {
            sync()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observe()
            }
        }
    }

    private func sync() {
        let running = runner.runningPaths
        let outcome = runner.lastOutcome
        let pending = runner.pendingConfirmation

        guard settings.showRunningIndicator else {
            // A pending confirmation has no surface without the indicator;
            // don't leave a zombie run waiting for a press that can't come.
            runner.cancelPending()
            flashTask?.cancel()
            flashTask = nil
            isFlashing = false
            lastHandledOutcome = outcome
            setState(.hidden)
            return
        }

        // A new outcome always flashes, including pre-flight refusals that
        // never enter runningPaths — same signal as the notification.
        if let outcome, outcome != lastHandledOutcome {
            lastHandledOutcome = outcome
            beginFlash(outcome)
            return
        }

        // An active flash holds the pill until its timer fires.
        guard !isFlashing else { return }

        // A question outranks progress: other tasks may run in parallel, but
        // the pending one needs an answer before the timeout clears it.
        if let pending {
            setState(.awaitingConfirmation(name: Self.abbreviate(pending.taskName, limit: 24)))
        } else if let primary = running.sorted().first {
            setState(.running(
                primaryName: Self.abbreviate(nameForPath(primary)),
                extraCount: running.count - 1
            ))
        } else {
            setState(.hidden)
        }
    }

    // MARK: - Confirmation passthroughs (called by the notch's buttons)

    func confirmPending() {
        runner.confirmPending()
    }

    func cancelPending() {
        runner.cancelPending()
    }

    private func beginFlash(_ outcome: RunOutcome) {
        isFlashing = true
        // The pill is glanceable: show only the headline ("Summarize
        // finished"); the notification and window status bar carry the rest.
        let headline = outcome.message.components(separatedBy: " — ").first ?? outcome.message
        setState(.flash(kind: outcome.kind, message: Self.abbreviate(headline)))
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: Self.flashDuration)
            guard !Task.isCancelled, let self else { return }
            self.isFlashing = false
            self.sync()
        }
    }

    // MARK: - Panel

    private func setState(_ new: IndicatorState) {
        guard state != new else { return }
        if new == .hidden {
            state = .hidden
            hideTask?.cancel()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: Self.hideDelay)
                guard !Task.isCancelled, let self, self.state == .hidden else { return }
                self.panel?.orderOut(nil)
            }
        } else {
            hideTask?.cancel()
            hideTask = nil
            showPanel()
            state = new
        }
        // The panel takes clicks only while asking a question; in every other
        // state it stays a click-through overlay.
        if case .awaitingConfirmation = new {
            panel?.ignoresMouseEvents = false
        } else {
            panel?.ignoresMouseEvents = true
        }
    }

    private func showPanel() {
        guard let screen = Self.targetScreen() else { return }
        geometry = IndicatorGeometry.measure(screen)
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let size = Self.stageSize
        panel.setFrame(
            NSRect(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.maxY - size.height,
                width: size.width,
                height: size.height
            ),
            display: true
        )
        panel.orderFrontRegardless()
    }

    /// A wing has no room for prose; the bar must never outgrow its stage.
    private static func abbreviate(_ text: String, limit: Int = 40) -> String {
        text.count <= limit ? text : text.prefix(limit).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The built-in notched display when present, otherwise wherever the
    /// menu bar is.
    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    /// Lid closed, display plugged in, resolution changed: re-measure and,
    /// if the pill is up, move it to the (possibly new) target screen.
    private func screenParametersChanged() {
        if let panel, panel.isVisible {
            showPanel()
        } else if let screen = Self.targetScreen() {
            geometry = IndicatorGeometry.measure(screen)
        }
    }

    private func makePanel() -> NotchIndicatorPanel {
        let panel = NotchIndicatorPanel(
            contentRect: NSRect(origin: .zero, size: Self.stageSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // .statusBar draws above the menu bar; with .fullScreenAuxiliary it
        // also shows over full-screen apps without outranking system alerts.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // A window shadow under the fake-notch shape would break the illusion
        // against the real notch; the floating capsule draws its own.
        panel.hasShadow = false
        // NSPanel defaults to hiding on deactivate, which for a background
        // app means the pill would vanish immediately.
        panel.hidesOnDeactivate = false
        // Never set isFloatingPanel here: its setter resets the window level
        // to .floating, dropping the panel below the menu bar — which both
        // breaks the drawn-over-the-menu-bar look and routes clicks meant
        // for the confirmation buttons to the menu bar instead.
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.animationBehavior = .none
        let host = FirstMouseHostingView(rootView: NotchIndicatorView(controller: self))
        host.frame = NSRect(origin: .zero, size: Self.stageSize)
        panel.contentView = host
        return panel
    }
}

/// The panel never becomes key, so every click on it is a "first mouse";
/// without this the confirmation buttons would need two clicks.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
