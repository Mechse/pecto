import AppKit

/// The transparent, click-through stage the indicator is drawn on. A fixed
/// frame hugging the top of the screen; all show/hide animation happens in
/// SwiftUI inside it, so the panel itself never moves or resizes.
final class NotchIndicatorPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// AppKit constrains window frames to below the menu bar; the whole point
    /// of this panel is to sit flush against the top edge, over the notch.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// What the indicator view needs to know about the screen it sits on.
struct IndicatorGeometry: Equatable {
    let hasNotch: Bool
    /// Physical notch width; 0 on screens without one.
    let notchWidth: CGFloat
    /// Height of the strip the shape must clear: the notch (safe-area inset)
    /// on notched displays, the menu bar elsewhere.
    let topInset: CGFloat

    static func measure(_ screen: NSScreen) -> IndicatorGeometry {
        let inset = screen.safeAreaInsets.top
        if inset > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            return IndicatorGeometry(
                hasNotch: true,
                notchWidth: max(0, screen.frame.width - left - right),
                topInset: inset
            )
        }
        return IndicatorGeometry(
            hasNotch: false,
            notchWidth: 0,
            topInset: screen.frame.maxY - screen.visibleFrame.maxY
        )
    }
}
