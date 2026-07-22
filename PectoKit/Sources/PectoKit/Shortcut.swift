import Foundation

/// The modifier keys a global shortcut can carry. Deliberately independent of
/// Carbon's `cmdKey`/`optionKey`/… masks so this type stays testable and free
/// of platform headers; `HotkeyManager` converts at the registration boundary.
public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let command = ShortcutModifiers(rawValue: 1 << 0)
    public static let option = ShortcutModifiers(rawValue: 1 << 1)
    public static let control = ShortcutModifiers(rawValue: 1 << 2)
    public static let shift = ShortcutModifiers(rawValue: 1 << 3)

    /// Glyphs in the order Apple prints them on menu items.
    public var display: String {
        var out = ""
        if contains(.control) { out += "⌃" }
        if contains(.option) { out += "⌥" }
        if contains(.shift) { out += "⇧" }
        if contains(.command) { out += "⌘" }
        return out
    }
}

/// A recorded system-wide key combination: a virtual key code plus modifiers.
public struct Shortcut: Codable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers

    public init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // MARK: - Persistence

    /// Stable, human-inspectable form stored in UserDefaults: "6-17".
    public var rawValue: String {
        "\(modifiers.rawValue)-\(keyCode)"
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let mods = Int(parts[0]),
              let code = UInt16(parts[1]),
              mods >= 0
        else { return nil }
        self.init(keyCode: code, modifiers: ShortcutModifiers(rawValue: mods))
    }

    // MARK: - Display

    /// Menu-style rendering, e.g. "⌃⌥T".
    public var display: String {
        modifiers.display + Self.keyName(for: keyCode)
    }

    /// Shift alone cannot carry a global shortcut — ⇧A would swallow a plain
    /// capital letter in every app — so at least one of ⌘/⌃/⌥ is required.
    public var hasRequiredModifier: Bool {
        !modifiers.intersection([.command, .option, .control]).isEmpty
    }

    // MARK: - Migration

    /// Slot 1–9 from the pre-recording shortcut model → its fixed ⌃⌥N combo.
    public static func legacySlot(_ slot: Int) -> Shortcut? {
        // kVK_ANSI_1 … kVK_ANSI_9 — deliberately non-sequential.
        let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        guard (1...digitKeyCodes.count).contains(slot) else { return nil }
        return Shortcut(keyCode: digitKeyCodes[slot - 1], modifiers: [.control, .option])
    }

    // MARK: - Key names

    /// ANSI layout plus the named keys a recorder can realistically produce.
    /// Anything else renders as its raw code rather than silently vanishing.
    public static func keyName(for keyCode: UInt16) -> String {
        if let name = namedKeys[keyCode] { return name }
        return "Key \(keyCode)"
    }

    private static let namedKeys: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        65: "Numpad .", 67: "Numpad *", 69: "Numpad +", 71: "Numpad Clear",
        75: "Numpad /", 78: "Numpad -", 81: "Numpad =",
        82: "Numpad 0", 83: "Numpad 1", 84: "Numpad 2", 85: "Numpad 3",
        86: "Numpad 4", 87: "Numpad 5", 88: "Numpad 6", 89: "Numpad 7",
        91: "Numpad 8", 92: "Numpad 9",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
        114: "Help", 115: "Home", 116: "Page Up", 119: "End", 121: "Page Down",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}
