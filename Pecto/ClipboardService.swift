import AppKit

@MainActor
enum ClipboardService {
    static func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    static func writeText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
