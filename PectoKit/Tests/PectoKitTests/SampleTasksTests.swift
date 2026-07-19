import Testing
@testable import PectoKit

@Suite struct SampleTasksTests {
    @Test func samplesParseAndAreSlotRunnable() throws {
        for (fileName, content) in SampleTasks.all {
            let task = try parseTask(content)
            #expect(fileName == "\(task.frontmatter.name).md")
            #expect(slotRunnability(instructions: task.instructions) == .runnable(needsClipboard: true))
        }
    }
}
