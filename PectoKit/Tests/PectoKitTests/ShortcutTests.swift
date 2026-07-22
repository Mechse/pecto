import Testing
@testable import PectoKit

@Suite struct ShortcutTests {
    @Test func rawValueRoundTrips() throws {
        let shortcut = Shortcut(keyCode: 17, modifiers: [.control, .option])
        #expect(Shortcut(rawValue: shortcut.rawValue) == shortcut)
    }

    @Test func malformedRawValuesAreRejected() {
        #expect(Shortcut(rawValue: "") == nil)
        #expect(Shortcut(rawValue: "6") == nil)
        #expect(Shortcut(rawValue: "six-17") == nil)
        #expect(Shortcut(rawValue: "6-T") == nil)
        #expect(Shortcut(rawValue: "6-17-3") == nil)
        #expect(Shortcut(rawValue: "-6-17") == nil)
    }

    @Test func displayUsesAppleGlyphOrder() {
        let all = Shortcut(keyCode: 17, modifiers: [.command, .shift, .option, .control])
        #expect(all.display == "⌃⌥⇧⌘T")
        #expect(Shortcut(keyCode: 49, modifiers: [.command]).display == "⌘Space")
    }

    @Test func unknownKeyCodesFallBackToTheirRawCode() {
        #expect(Shortcut(keyCode: 200, modifiers: [.command]).display == "⌘Key 200")
    }

    @Test func shiftAloneIsNotASufficientModifier() {
        #expect(!Shortcut(keyCode: 0, modifiers: [.shift]).hasRequiredModifier)
        #expect(!Shortcut(keyCode: 0, modifiers: []).hasRequiredModifier)
        #expect(Shortcut(keyCode: 0, modifiers: [.shift, .command]).hasRequiredModifier)
        #expect(Shortcut(keyCode: 0, modifiers: [.control]).hasRequiredModifier)
        #expect(Shortcut(keyCode: 0, modifiers: [.option]).hasRequiredModifier)
    }

    @Test func legacySlotsMapToTheirOldCombos() {
        #expect(Shortcut.legacySlot(3) == Shortcut(keyCode: 20, modifiers: [.control, .option]))
        #expect(Shortcut.legacySlot(1)?.display == "⌃⌥1")
        #expect(Shortcut.legacySlot(9)?.display == "⌃⌥9")
        #expect(Shortcut.legacySlot(0) == nil)
        #expect(Shortcut.legacySlot(10) == nil)
    }
}
