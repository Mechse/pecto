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
    /// The cursor is near the indicator, so it shows its details.
    private(set) var isExpanded = false

    /// Room for the bar at its widest and the expanded card at its tallest;
    /// the panel never resizes, so the stage is sized for the largest state
    /// and stays transparent (and click-through) everywhere else.
    private static let stageSize = NSSize(width: 1000, height: 420)
    private static let flashDuration: Duration = .seconds(2.5)
    /// What's left of the flash after the cursor leaves a held one — long
    /// enough to register the result, short enough not to linger.
    private static let flashTail: Duration = .milliseconds(1200)
    /// Long enough for the shrink-away transition to finish before orderOut.
    private static let hideDelay: Duration = .milliseconds(450)

    private let runner: RunCoordinator
    private let settings: SettingsStore
    private let nameForPath: (String) -> String

    private var panel: NotchIndicatorPanel?
    private var host: NotchHitTestingView<NotchIndicatorView>?
    private var hoverMonitor: NotchHoverMonitor?
    /// Last shape rect reported by the view, kept so the hot zone can be
    /// recomputed when the panel moves without the shape changing.
    private var shapeRect: CGRect = .zero
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

    // MARK: - What the expanded card shows

    /// In-flight runs, oldest first — the order they'll finish in, roughly,
    /// and stable while the card is open.
    var activeRuns: [ActiveRun] {
        runner.activeRuns.values.sorted { $0.startedAt < $1.startedAt }
    }

    /// The last result worth offering again: text output from a success.
    var lastOutput: String? {
        guard let outcome = runner.lastOutcome, outcome.kind == .success else { return nil }
        return outcome.output
    }

    var lastOutputTaskName: String? {
        runner.lastOutcome.map { nameForPath($0.taskPath) }
    }

    // MARK: - Actions (called by the notch's buttons)

    func confirmPending() {
        runner.confirmPending()
    }

    func cancelPending() {
        runner.cancelPending()
    }

    func cancelRun(path: String) {
        runner.cancel(path: path)
    }

    /// Puts the last result back on the clipboard — the point of keeping it
    /// around is that you may have copied something else since.
    func copyLastOutput() {
        guard let text = lastOutput else { return }
        ClipboardService.writeText(text)
    }

    // MARK: - Expansion

    /// Reported by the view: the visible shape's rect inside the stage, in
    /// SwiftUI's top-left coordinates. It's the single source for both the
    /// hover hot zone and the panel's hit region, so the two can never
    /// disagree — you can always click what you just hovered open.
    func shapeRectChanged(_ rect: CGRect) {
        shapeRect = rect
        refreshHotZone()
    }

    private func refreshHotZone() {
        guard let panel, shapeRect != .zero else { return }
        host?.interactiveRect = shapeRect
        let margin: CGFloat = isExpanded ? 16 : 10
        hoverMonitor?.hotZone = CGRect(
            x: panel.frame.minX + shapeRect.minX,
            // SwiftUI measures from the top; screen coordinates run upward.
            y: panel.frame.maxY - shapeRect.maxY,
            width: shapeRect.width,
            height: shapeRect.height
        ).insetBy(dx: -margin, dy: -margin)
    }

    private func setExpanded(_ expanded: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded
        updateMouseHandling()
        // Widen the zone immediately on expand; the view reports the card's
        // real rect a frame later.
        refreshHotZone()
        // A flash under the cursor is being read; hold it open and leave only
        // a short tail once the cursor goes away.
        if isFlashing {
            flashTask?.cancel()
            flashTask = expanded ? nil : makeFlashTask(after: Self.flashTail)
        }
    }

    /// The panel takes clicks while it's asking a question or showing its
    /// details; in every other state it stays a click-through overlay so the
    /// menu bar underneath keeps working.
    private func updateMouseHandling() {
        let interactive = isExpanded || { if case .awaitingConfirmation = state { true } else { false } }()
        panel?.ignoresMouseEvents = !interactive
    }

    private func beginFlash(_ outcome: RunOutcome) {
        isFlashing = true
        // The pill is glanceable: show only the headline ("Summarize
        // finished"); the notification and window status bar carry the rest.
        let headline = outcome.message.components(separatedBy: " — ").first ?? outcome.message
        setState(.flash(kind: outcome.kind, message: Self.abbreviate(headline)))
        flashTask?.cancel()
        // A flash that arrives while the card is open waits for the cursor to
        // leave, the same as one hovered mid-flight.
        flashTask = isExpanded ? nil : makeFlashTask(after: Self.flashDuration)
    }

    private func makeFlashTask(after duration: Duration) -> Task<Void, Never> {
        Task { [weak self] in
            try? await Task.sleep(for: duration)
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
            // Nothing left to look at: stop tracking and collapse, so the
            // next run never opens pre-expanded under a parked cursor.
            hoverMonitor?.stop()
            isExpanded = false
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
            hoverMonitor?.start()
        }
        updateMouseHandling()
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
        // The panel may have landed on a different screen; the shape sits at
        // a new place in screen coordinates even if its rect on the stage is
        // unchanged.
        refreshHotZone()
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
        let host = NotchHitTestingView(rootView: NotchIndicatorView(controller: self))
        host.frame = NSRect(origin: .zero, size: Self.stageSize)
        panel.contentView = host
        self.host = host
        hoverMonitor = NotchHoverMonitor { [weak self] hovering in
            self?.setExpanded(hovering)
        }
        return panel
    }
}

/// The stage is far larger than the shape drawn on it. While the panel takes
/// clicks at all, only the visible shape may swallow them — the rest of the
/// stage sits over the menu bar and must stay transparent to the mouse.
///
/// Also: the panel never becomes key, so every click on it is a "first
/// mouse"; without that override the buttons would need two clicks.
private final class NotchHitTestingView<Content: View>: NSHostingView<Content> {
    /// The visible shape, in SwiftUI's top-left coordinates.
    var interactiveRect: CGRect = .zero

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        // NSHostingView is flipped, so its coordinates already match the
        // rect SwiftUI reported — but don't bet the hit region on that.
        let topLeft = isFlipped ? local : NSPoint(x: local.x, y: bounds.height - local.y)
        guard interactiveRect.contains(topLeft) else { return nil }
        return super.hitTest(point)
    }
}
