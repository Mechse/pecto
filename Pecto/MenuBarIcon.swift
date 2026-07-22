import AppKit

/// Images for the status item. The mark is the app icon's two sparkles
/// (design/menubaricon.svg, exported by scripts/make-menubar-icon.sh) without
/// the Dock icon's rounded square, so it reads as Pecto in the menu bar.
///
/// Idle is a plain template image — macOS inverts it for light/dark menu bars
/// and tints it while the menu is open. Running keeps the same glyph but turns
/// the small accent sparkle brand green, which a template image cannot express,
/// hence the two-part composite.
@MainActor
enum MenuBarIcon {
    /// Brand green, matching the accent sparkle in design/appicon.svg.
    private static let accentColor = NSColor(
        srgbRed: 0x12 / 255, green: 0xA3 / 255, blue: 0x67 / 255, alpha: 1)

    static let idle: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(size: .zero)
        image.isTemplate = true
        return image
    }()

    /// Composited lazily on every draw: the handler runs under the current
    /// appearance, so `labelColor` resolves correctly on a light or dark menu
    /// bar without observing appearance changes ourselves.
    static let running: NSImage = {
        let glyph = NSImage(named: "MenuBarIconGlyph") ?? NSImage(size: .zero)
        let accent = NSImage(named: "MenuBarIconAccent") ?? NSImage(size: .zero)

        let image = NSImage(size: glyph.size, flipped: false) { rect in
            glyph.tinted(with: .labelColor).draw(in: rect)
            accent.tinted(with: accentColor).draw(in: rect)
            return true
        }
        // Colour must survive, so this one is not a template.
        image.isTemplate = false
        return image
    }()
}

private extension NSImage {
    /// Recolours a template image by filling its opaque pixels.
    func tinted(with color: NSColor) -> NSImage {
        let copy = NSImage(size: size, flipped: false) { rect in
            self.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        copy.isTemplate = false
        return copy
    }
}
