import Testing
@testable import PectoKit

@Suite struct SlotRunnabilityTests {
    @Test func noPlaceholdersIsRunnable() {
        #expect(slotRunnability(instructions: "Write a haiku about autumn.") == .runnable(needsClipboard: false))
    }

    @Test func clipboardOnlyIsRunnable() {
        #expect(slotRunnability(instructions: "Improve this: {{clipboard}} and again {{ clipboard }}") == .runnable(needsClipboard: true))
    }

    @Test func foreignPlaceholderIsNotRunnable() {
        let result = slotRunnability(instructions: "Needs {{email_draft}} and {{tone}}.")
        guard case .notRunnable(let reason) = result else {
            Issue.record("expected notRunnable, got \(result)")
            return
        }
        #expect(reason.contains("{{email_draft}}, {{tone}}"))
        #expect(reason.contains("{{clipboard}}"))
    }

    @Test func clipboardMixedWithForeignIsNotRunnable() {
        let result = slotRunnability(instructions: "{{clipboard}} plus {{extra}}")
        guard case .notRunnable(let reason) = result else {
            Issue.record("expected notRunnable, got \(result)")
            return
        }
        #expect(reason.contains("{{extra}}"))
        #expect(!reason.contains("{{clipboard}},"))
    }
}
