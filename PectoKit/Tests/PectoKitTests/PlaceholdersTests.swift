import Testing
@testable import PectoKit

@Suite struct PlaceholdersTests {
    @Test func extractsInOrderDeduplicated() {
        let text = "Use {{tone}} and {{draft}}, then {{tone}} again."
        #expect(extractPlaceholders(text) == ["tone", "draft"])
    }

    @Test func allowsWhitespaceInsideBraces() {
        #expect(extractPlaceholders("Hello {{ clipboard }}!") == ["clipboard"])
    }

    @Test func rejectsInvalidNames() {
        #expect(extractPlaceholders("{{1st}} {{-x}} {{}} {{ }} {single} {{a b}}").isEmpty)
    }

    @Test func labels() {
        #expect(placeholderLabel("email_draft") == "Email draft")
        #expect(placeholderLabel("target-audience") == "Target audience")
        #expect(placeholderLabel("tone") == "Tone")
        #expect(placeholderLabel("a__weird--name") == "A weird name")
    }

    @Test func fillsKnownNames() {
        let filled = fillPlaceholders("Improve: {{clipboard}}", values: ["clipboard": "my draft"])
        #expect(filled == "Improve: my draft")
    }

    /// A confirmed empty-clipboard run substitutes empty text, not the
    /// placeholder verbatim.
    @Test func fillsEmptyValues() {
        let filled = fillPlaceholders("Improve: {{clipboard}}", values: ["clipboard": ""])
        #expect(filled == "Improve: ")
    }

    @Test func fillsWhitespaceVariants() {
        let filled = fillPlaceholders("Improve: {{ clipboard }}", values: ["clipboard": "my draft"])
        #expect(filled == "Improve: my draft")
    }

    @Test func leavesUnknownNamesVerbatim() {
        let filled = fillPlaceholders("Keep {{ mystery }} and fill {{known}}.", values: ["known": "this"])
        #expect(filled == "Keep {{ mystery }} and fill this.")
    }

    @Test func doesNotRescanSubstitutedValues() {
        let filled = fillPlaceholders("{{a}}", values: ["a": "{{b}}", "b": "nope"])
        #expect(filled == "{{b}}")
    }
}
