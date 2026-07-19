import Foundation
import Testing
@testable import PectoKit

private func makeStore() throws -> HistoryStore {
    try HistoryStore(path: ":memory:")
}

private func makeRun(
    id: String = "run-1",
    taskPath: String = "improve-email.md",
    startedAt: Int = 1_000,
    status: RunStatus = .succeeded,
    output: String? = "better email",
    error: String? = nil,
    inputs: [String: String]? = ["clipboard": "raw email"]
) -> RunRecord {
    RunRecord(
        id: id,
        taskPath: taskPath,
        startedAt: startedAt,
        finishedAt: startedAt + 1_500,
        status: status,
        model: "claude-sonnet-4-5",
        inputTokens: 89,
        outputTokens: 35,
        output: output,
        error: error,
        inputs: inputs
    )
}

@Suite struct HistoryStoreTests {
    @Test func recordsAndListsRunsNewestFirst() throws {
        let store = try makeStore()
        store.recordRun(makeRun(id: "run-1", startedAt: 1_000))
        store.recordRun(makeRun(id: "run-2", startedAt: 2_000))
        store.recordRun(makeRun(id: "other", taskPath: "summarize-text.md"))

        let runs = store.listRuns(taskPath: "improve-email.md")
        #expect(runs.map(\.id) == ["run-2", "run-1"])
        #expect(runs[0] == makeRun(id: "run-2", startedAt: 2_000))
    }

    @Test func roundtripsNullableFieldsAndInputs() throws {
        let store = try makeStore()
        let failed = RunRecord(
            id: "run-f", taskPath: "t.md", startedAt: 1, finishedAt: 2,
            status: .failed, model: "claude-sonnet-4-5",
            inputTokens: nil, outputTokens: nil, output: nil,
            error: "Rate limited.", inputs: nil
        )
        store.recordRun(failed)
        #expect(store.listRuns(taskPath: "t.md") == [failed])
    }

    @Test func firstSnapshotIsPureAdditions() throws {
        let store = try makeStore()
        let snapshot = store.recordSnapshot(taskPath: "t.md", kind: .created, content: "a\nb\nc", at: 1)
        #expect(snapshot?.linesAdded == 3)
        #expect(snapshot?.linesRemoved == 0)
    }

    @Test func editSnapshotsDiffAgainstPrevious() throws {
        let store = try makeStore()
        store.recordSnapshot(taskPath: "t.md", kind: .created, content: "a\nb\nc", at: 1)
        let edit = store.recordSnapshot(taskPath: "t.md", kind: .edited, content: "a\nc\nd", at: 2)
        #expect(edit?.linesAdded == 1)
        #expect(edit?.linesRemoved == 1)
    }

    @Test func skipsNoOpEditsAndRestores() throws {
        let store = try makeStore()
        store.recordSnapshot(taskPath: "t.md", kind: .created, content: "same", at: 1)
        #expect(store.recordSnapshot(taskPath: "t.md", kind: .edited, content: "same", at: 2) == nil)
        #expect(store.recordSnapshot(taskPath: "t.md", kind: .restored, content: "same", at: 3) == nil)
        #expect(store.listSnapshots(taskPath: "t.md").count == 1)
    }

    @Test func getSnapshotCarriesPrevContentForDiffs() throws {
        let store = try makeStore()
        let first = store.recordSnapshot(taskPath: "t.md", kind: .created, content: "one", at: 1)
        let second = store.recordSnapshot(taskPath: "t.md", kind: .edited, content: "two", at: 2)

        let loadedFirst = store.getSnapshot(id: first!.id)
        #expect(loadedFirst?.content == "one")
        #expect(loadedFirst?.prevContent == "")

        let loadedSecond = store.getSnapshot(id: second!.id)
        #expect(loadedSecond?.content == "two")
        #expect(loadedSecond?.prevContent == "one")
        #expect(loadedSecond?.record.kind == .edited)
        #expect(store.getSnapshot(id: 999) == nil)
    }

    @Test func renameMigratesHistoryAndMarksIt() throws {
        let store = try makeStore()
        store.recordRun(makeRun(taskPath: "old.md"))
        store.recordSnapshot(taskPath: "old.md", kind: .created, content: "body", at: 1)

        store.renameTask(from: "old.md", to: "new.md", content: "body", at: 2)

        #expect(store.listRuns(taskPath: "old.md").isEmpty)
        #expect(store.listRuns(taskPath: "new.md").count == 1)
        #expect(store.listSnapshots(taskPath: "old.md").isEmpty)

        let snapshots = store.listSnapshots(taskPath: "new.md")
        #expect(snapshots.count == 2)
        #expect(snapshots[0].kind == .renamed)
        #expect(snapshots[0].renamedFrom == "old.md")
        #expect(snapshots[0].linesAdded == 0)
        #expect(snapshots[0].linesRemoved == 0)
    }

    @Test func deleteDropsAllHistory() throws {
        let store = try makeStore()
        store.recordRun(makeRun(taskPath: "doomed.md"))
        store.recordSnapshot(taskPath: "doomed.md", kind: .created, content: "x", at: 1)
        store.recordRun(makeRun(id: "keep", taskPath: "kept.md"))

        store.deleteTask(taskPath: "doomed.md")

        #expect(store.listRuns(taskPath: "doomed.md").isEmpty)
        #expect(store.listSnapshots(taskPath: "doomed.md").isEmpty)
        #expect(store.listRuns(taskPath: "kept.md").count == 1)
    }

    @Test func persistsToDiskUnderDotPecto() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pecto-history-\(UUID().uuidString)")
        let dbPath = root.appendingPathComponent(".pecto/pecto.db").path
        do {
            let store = try HistoryStore(path: dbPath)
            store.recordRun(makeRun())
        }
        let reopened = try HistoryStore(path: dbPath)
        #expect(reopened.listRuns(taskPath: "improve-email.md").count == 1)

        // The .pecto folder must stay invisible to the task list.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        #expect(try WorkspaceStore(root: root).listTasks().isEmpty)
    }
}
