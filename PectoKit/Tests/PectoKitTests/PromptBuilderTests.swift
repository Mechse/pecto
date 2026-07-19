import Testing
@testable import PectoKit

@Suite struct PromptBuilderTests {
    @Test func buildsSystemAndUserPrompt() {
        let prompt = buildPrompt(
            task: TaskFrontmatter(name: "improve-email", description: "Polish an email draft"),
            filledInstructions: "Improve this: my draft"
        )
        #expect(prompt.system == """
        You are executing the task "improve-email": Polish an email draft.
        Follow the instructions exactly. Reply with only the final result of the task — no preamble.
        """)
        #expect(prompt.user == "Improve this: my draft")
    }
}

@Suite struct TaskTemplateTests {
    @Test func templateMatchesLegacyFormat() {
        #expect(newTaskTemplate(name: "my-task") ==
            "---\nname: my-task\ndescription: Describe what this task does in one line.\n---\n\nWrite plain-language instructions for what should happen when this task runs.\n")
    }

    @Test func templateParsesAndIsSlotRunnable() throws {
        let task = try parseTask(newTaskTemplate(name: "fresh-task"))
        #expect(task.frontmatter.name == "fresh-task")
        #expect(slotRunnability(instructions: task.instructions) == .runnable(needsClipboard: false))
    }
}
