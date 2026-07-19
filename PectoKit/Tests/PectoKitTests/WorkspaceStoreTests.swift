import Foundation
import Testing
@testable import PectoKit

private func makeWorkspace() throws -> WorkspaceStore {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("pecto-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return WorkspaceStore(root: url)
}

private func errorMessage(_ body: () throws -> Void) -> String? {
    do {
        try body()
        return nil
    } catch let error as TaskParseError {
        return error.message
    } catch {
        return "unexpected error type"
    }
}

@Suite struct WorkspaceStoreTests {
    @Test func createListReadRoundtrip() throws {
        let workspace = try makeWorkspace()
        try workspace.createTask("my-task.md")
        let tasks = try workspace.listTasks()
        #expect(tasks.map(\.path) == ["my-task.md"])
        #expect(tasks[0].name == "my-task")
        #expect(tasks[0].error == nil)
        #expect(try workspace.readFile("my-task.md") == newTaskTemplate(name: "my-task"))
    }

    @Test func listIgnoresDotfilesDirectoriesAndNonMarkdown() throws {
        let workspace = try makeWorkspace()
        try workspace.createTask("b-task.md")
        try workspace.createTask("a-task.md")
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: workspace.root.appendingPathComponent("folder.md"), withIntermediateDirectories: true)
        try "hidden".write(to: workspace.root.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
        try "notes".write(to: workspace.root.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        #expect(try workspace.listTasks().map(\.path) == ["a-task.md", "b-task.md"])
    }

    @Test func listSurfacesParseErrorsPerFile() throws {
        let workspace = try makeWorkspace()
        try "no frontmatter here".write(to: workspace.root.appendingPathComponent("broken.md"), atomically: true, encoding: .utf8)
        let tasks = try workspace.listTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].name == nil)
        #expect(tasks[0].error ==
            "This file is missing its settings block. A task starts with a section between two '---' lines that names the task and describes what it needs.")
    }

    @Test func listReportsPlaceholders() throws {
        let workspace = try makeWorkspace()
        try workspace.writeFile("clip.md", content: "---\nname: clip\ndescription: Uses the clipboard\n---\n\nImprove {{clipboard}}.")
        #expect(try workspace.listTasks()[0].placeholders == ["clipboard"])
    }

    @Test func createRejectsBadNames() throws {
        let workspace = try makeWorkspace()
        #expect(errorMessage { try workspace.createTask("task.txt") } == "Task files end in .md.")
        #expect(errorMessage { try workspace.createTask("Bad Name.md") } ==
            "Task file names use lowercase letters, numbers and dashes (e.g. enrich-new-signups).")
    }

    @Test func createRejectsDuplicates() throws {
        let workspace = try makeWorkspace()
        try workspace.createTask("dupe.md")
        #expect(errorMessage { try workspace.createTask("dupe.md") } == "Something with that name already exists.")
    }

    @Test func writeRejectsNonMarkdown() throws {
        let workspace = try makeWorkspace()
        #expect(errorMessage { try workspace.writeFile("evil.sh", content: "#!/bin/sh") } == "Only .md task files can be saved.")
    }

    @Test func renameMovesAndValidates() throws {
        let workspace = try makeWorkspace()
        try workspace.createTask("old-name.md")
        try workspace.renameTask(from: "old-name.md", to: "new-name.md")
        #expect(try workspace.listTasks().map(\.path) == ["new-name.md"])

        try workspace.createTask("other.md")
        #expect(errorMessage { try workspace.renameTask(from: "new-name.md", to: "other.md") } == "Something with that name already exists.")
        #expect(errorMessage { try workspace.renameTask(from: "missing.md", to: "wherever.md") } == "This file no longer exists.")
        #expect(errorMessage { try workspace.renameTask(from: "new-name.md", to: "Bad Name.md") } ==
            "Task file names use lowercase letters, numbers and dashes (e.g. enrich-new-signups).")
    }

    @Test func deleteRemovesAndValidates() throws {
        let workspace = try makeWorkspace()
        try workspace.createTask("doomed.md")
        try workspace.deleteTask("doomed.md")
        #expect(try workspace.listTasks().isEmpty)
        #expect(errorMessage { try workspace.deleteTask("doomed.md") } == "This file no longer exists.")
        #expect(errorMessage { try workspace.deleteTask("nope.txt") } == "Only .md task files can be deleted.")
    }

    @Test func refusesPathsOutsideWorkspace() throws {
        let workspace = try makeWorkspace()
        #expect(errorMessage { _ = try workspace.readFile("../outside.md") } == "That file is outside the workspace.")
        #expect(errorMessage { try workspace.writeFile("../outside.md", content: "x") } == "That file is outside the workspace.")
        #expect(errorMessage { try workspace.deleteTask("../outside.md") } == "That file is outside the workspace.")
    }

    @Test func readMissingFile() throws {
        let workspace = try makeWorkspace()
        #expect(errorMessage { _ = try workspace.readFile("ghost.md") } == "This file no longer exists.")
    }
}
