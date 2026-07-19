import Testing
@testable import PectoKit

private let sample = """
---
name: improve-email
description: Polish an email draft without losing the sender's voice.
---

Improve the email draft below.

{{clipboard}}
"""

private func parseErrorMessage(_ markdown: String) -> String? {
    do {
        _ = try parseTask(markdown)
        return nil
    } catch let error as TaskParseError {
        return error.message
    } catch {
        return "unexpected error type"
    }
}

@Suite struct TaskParserTests {
    @Test func parsesValidTask() throws {
        let task = try parseTask(sample)
        #expect(task.frontmatter == TaskFrontmatter(
            name: "improve-email",
            description: "Polish an email draft without losing the sender's voice."
        ))
        #expect(task.instructions == "Improve the email draft below.\n\n{{clipboard}}")
        #expect(task.raw == sample)
    }

    @Test func keepsRawUntrimmedAndAllowsLeadingWhitespace() throws {
        let padded = "\n\n  " + sample
        let task = try parseTask(padded)
        #expect(task.frontmatter.name == "improve-email")
        #expect(task.raw == padded)
    }

    @Test func handlesCRLFLineEndings() throws {
        let crlf = "---\r\nname: crlf-task\r\ndescription: Windows line endings\r\n---\r\nDo the thing."
        let task = try parseTask(crlf)
        #expect(task.frontmatter.name == "crlf-task")
        #expect(task.instructions == "Do the thing.")
    }

    @Test func ignoresUnknownFrontmatterKeys() throws {
        let markdown = """
        ---
        name: has-extras
        description: Carries fields from the future
        model: claude-sonnet-4-5
        inputs: whatever
        ---

        Instructions.
        """
        let task = try parseTask(markdown)
        #expect(task.frontmatter == TaskFrontmatter(name: "has-extras", description: "Carries fields from the future"))
    }

    @Test func missingFrontmatterBlock() {
        #expect(parseErrorMessage("Just some markdown with no settings.") ==
            "This file is missing its settings block. A task starts with a section between two '---' lines that names the task and describes what it needs.")
    }

    @Test func brokenYaml() {
        let markdown = "---\nname: \"unterminated\n---\n\nBody."
        #expect(parseErrorMessage(markdown) ==
            "The settings block at the top of this task could not be read. Check it for stray characters or broken indentation.")
    }

    @Test func nonMappingFrontmatter() {
        let markdown = "---\njust a scalar\n---\n\nBody."
        #expect(parseErrorMessage(markdown) == "The task settings are incomplete.")
    }

    @Test func missingName() {
        let markdown = "---\ndescription: No name here\n---\n\nBody."
        #expect(parseErrorMessage(markdown) == "Every task needs a name (name)")
    }

    @Test func emptyName() {
        let markdown = "---\nname: \"\"\ndescription: Empty name\n---\n\nBody."
        #expect(parseErrorMessage(markdown) == "Every task needs a name (name)")
    }

    @Test func badNameFormat() {
        let markdown = "---\nname: Not A Slug\ndescription: Bad name\n---\n\nBody."
        #expect(parseErrorMessage(markdown) ==
            "Task names use lowercase letters, numbers and dashes (e.g. enrich-new-signups) (name)")
    }

    @Test func missingDescription() {
        let markdown = "---\nname: no-description\n---\n\nBody."
        #expect(parseErrorMessage(markdown) == "Every task needs a one-line description (description)")
    }

    @Test func emptyBody() {
        let markdown = "---\nname: no-body\ndescription: Settings only\n---\n\n   \n"
        #expect(parseErrorMessage(markdown) ==
            "This task has settings but no instructions. Below the settings block, describe in plain language what should happen.")
    }

    @Test func bodylessFileWithoutTrailingNewline() {
        let markdown = "---\nname: no-body\ndescription: Settings only\n---"
        #expect(parseErrorMessage(markdown) ==
            "This task has settings but no instructions. Below the settings block, describe in plain language what should happen.")
    }

    @Test func slugRule() {
        #expect(isTaskSlug("enrich-new-signups"))
        #expect(isTaskSlug("a1-b2"))
        #expect(!isTaskSlug("-starts-with-dash"))
        #expect(!isTaskSlug("Has-Upper"))
        #expect(!isTaskSlug("has/slash"))
        #expect(!isTaskSlug(""))
    }
}
