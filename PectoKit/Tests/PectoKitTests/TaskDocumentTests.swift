import Testing
@testable import PectoKit

private let canonical = """
---
name: improve-email
description: Polish an email draft without losing the sender's voice.
---

Improve the email draft below.

{{clipboard}}

"""

@Suite struct TaskDocumentTests {
    @Test func roundTripIsByteStable() throws {
        let document = try parseDocument(canonical)
        let serialized = document.serialize()
        #expect(serialized == canonical)
        #expect(try parseDocument(serialized) == document)
    }

    @Test func serializesInFixedKeyOrder() {
        let document = TaskDocument(
            frontmatter: TaskFrontmatter(name: "t", description: "A task.", model: "claude-haiku-4-5"),
            body: "Do the thing."
        )
        #expect(document.serialize() == """
        ---
        name: t
        description: A task.
        model: claude-haiku-4-5
        ---

        Do the thing.

        """)
    }

    @Test func omitsModelWhenNil() throws {
        let document = try parseDocument(canonical)
        #expect(document.frontmatter.model == nil)
        #expect(!document.serialize().contains("model:"))
    }

    @Test func preservesUnknownKeysAndComments() throws {
        let markdown = """
        ---
        name: t
        # a comment someone left
        description: A task.
        inputs:
          - clipboard
        ---

        Body.
        """
        let document = try parseDocument(markdown)
        #expect(document.extraFrontmatterLines == ["# a comment someone left", "inputs:", "  - clipboard"])
        let serialized = document.serialize()
        #expect(serialized == """
        ---
        name: t
        description: A task.
        # a comment someone left
        inputs:
          - clipboard
        ---

        Body.

        """)
        #expect(try parseDocument(serialized) == document)
    }

    @Test func quotesDescriptionsYAMLWouldMisread() throws {
        let document = TaskDocument(
            frontmatter: TaskFrontmatter(name: "t", description: "Summarize: keep \"quotes\" #intact"),
            body: "Body."
        )
        let reparsed = try parseDocument(document.serialize())
        #expect(reparsed.frontmatter.description == "Summarize: keep \"quotes\" #intact")
    }

    @Test func quotesBooleanAndNumericLookalikes() throws {
        for value in ["true", "no", "123", "3.14"] {
            let document = TaskDocument(
                frontmatter: TaskFrontmatter(name: "t", description: value),
                body: "Body."
            )
            let reparsed = try parseDocument(document.serialize())
            #expect(reparsed.frontmatter.description == value)
        }
    }

    @Test func allowsEmptyBody() throws {
        let document = try parseDocument("---\nname: t\ndescription: A task.\n---\n")
        #expect(document.body.isEmpty)
        #expect(document.serialize() == "---\nname: t\ndescription: A task.\n---\n")
    }

    @Test func repairsMissingFences() {
        let (document, wasRepaired) = loadDocumentRepairing("Just some prose.", fallbackName: "my-task")
        #expect(wasRepaired)
        #expect(document.frontmatter == TaskFrontmatter(name: "my-task", description: placeholderDescription))
        #expect(document.body == "Just some prose.")
        #expect(try! parseDocument(document.serialize()) == document)
    }

    @Test func repairsBrokenYAMLKeepingInstructions() {
        let markdown = """
        ---
        name: [broken
        ---

        The instructions survive.
        """
        let (document, wasRepaired) = loadDocumentRepairing(markdown, fallbackName: "my-task")
        #expect(wasRepaired)
        #expect(document.frontmatter.name == "my-task")
        #expect(document.body == "The instructions survive.")
        #expect(!document.serialize().contains("[broken"))
    }

    @Test func repairsMissingRequiredFields() {
        let markdown = "---\nname: only-a-name\n---\n\nBody.\n"
        let (document, wasRepaired) = loadDocumentRepairing(markdown, fallbackName: "only-a-name")
        #expect(wasRepaired)
        #expect(document.frontmatter.description == placeholderDescription)
        #expect(document.body == "Body.")
    }

    @Test func repairsEmptyFile() {
        let (document, wasRepaired) = loadDocumentRepairing("", fallbackName: "empty")
        #expect(wasRepaired)
        #expect(document.frontmatter.name == "empty")
        #expect(document.body.isEmpty)
    }

    @Test func repairFallsBackWhenFilenameIsNotASlug() {
        let (document, _) = loadDocumentRepairing("prose", fallbackName: "Not A Slug")
        #expect(document.frontmatter.name == "task")
    }

    @Test func newTaskTemplateRoundTrips() throws {
        let content = newTaskTemplate(name: "fresh-task")
        let document = try parseDocument(content)
        #expect(document.frontmatter.name == "fresh-task")
        #expect(document.frontmatter.description == placeholderDescription)
        #expect(document.serialize() == content)
    }
}
