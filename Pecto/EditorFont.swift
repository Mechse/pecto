import SwiftUI

/// Shared sizing for the task text editor, persisted via AppStorage.
enum EditorFont {
    static let sizeKey = "editorFontSize"
    static let defaultSize: Double = 14
    static let minSize: Double = 10
    static let maxSize: Double = 24
    /// Extra leading as a fraction of the font size (~1.3× line height).
    static let lineSpacingFactor: Double = 0.3

    static func clamped(_ size: Double) -> Double {
        min(max(size, minSize), maxSize)
    }
}

/// View-menu zoom commands for the editor font (⌘+ / ⌘− / ⌘0).
struct EditorFontCommands: Commands {
    @AppStorage(EditorFont.sizeKey) private var fontSize = EditorFont.defaultSize

    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Divider()

            Button("Increase Font Size") {
                fontSize = EditorFont.clamped(fontSize + 1)
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(fontSize >= EditorFont.maxSize)

            Button("Decrease Font Size") {
                fontSize = EditorFont.clamped(fontSize - 1)
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(fontSize <= EditorFont.minSize)

            Button("Reset Font Size") {
                fontSize = EditorFont.defaultSize
            }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(fontSize == EditorFont.defaultSize)
        }
    }
}
