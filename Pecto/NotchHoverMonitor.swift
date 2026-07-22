import AppKit

/// Watches whether the cursor is near the notch indicator.
///
/// Deliberately a poll of `NSEvent.mouseLocation` rather than an event
/// monitor: the strip sits over the menu bar, whose own tracking owns the
/// event stream up there, and a global `.mouseMoved` monitor is both less
/// reliable in that region and easy to confuse with a permissions problem.
/// A ~12 Hz poll that only runs while the indicator is on screen costs
/// nothing and can't interfere with anything.
///
/// Hysteresis lives here so the controller only ever sees a settled answer:
/// the cursor must dwell before the panel opens, and leave for a grace
/// period before it closes — a cursor swiping past the notch never flickers
/// it open, and reaching for a button just inside the edge never slams it
/// shut.
@MainActor
final class NotchHoverMonitor {
    /// Screen-coordinate rect the cursor must be inside; set by the
    /// controller and re-set whenever the shape or screen changes.
    var hotZone: CGRect = .zero

    private let onChange: (Bool) -> Void
    private var timer: Timer?
    private var isInside = false
    /// When the cursor first entered (or left) the zone, for the dwell and
    /// grace timings; nil once that transition has been reported.
    private var pendingSince: Date?

    private static let interval: TimeInterval = 0.08
    private static let enterDwell: TimeInterval = 0.18
    private static let exitGrace: TimeInterval = 0.25

    init(onChange: @escaping (Bool) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // The menu bar and menus run the main run loop in a tracking mode;
        // without this the poll would freeze exactly where it matters.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Stops polling and reports "not hovering" if it was, so the caller
    /// never keeps a stale expanded state after the panel goes away.
    func stop() {
        timer?.invalidate()
        timer = nil
        pendingSince = nil
        guard isInside else { return }
        isInside = false
        onChange(false)
    }

    private func tick() {
        let inZone = hotZone.contains(NSEvent.mouseLocation)
        guard inZone != isInside else {
            // Back on the settled side before the timing elapsed: no change.
            pendingSince = nil
            return
        }
        let since = pendingSince ?? Date()
        pendingSince = since
        let required = inZone ? Self.enterDwell : Self.exitGrace
        guard Date().timeIntervalSince(since) >= required else { return }
        pendingSince = nil
        isInside = inZone
        onChange(inZone)
    }
}
