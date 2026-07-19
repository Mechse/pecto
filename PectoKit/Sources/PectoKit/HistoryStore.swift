import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct HistoryStoreError: LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
}

/// Persistent history for a workspace: finished runs and task-content
/// snapshots, in a SQLite file under `<workspace>/.pecto/`. The task list
/// ignores dot-folders, so the store never shows up as a task.
///
/// Not thread-safe — the app confines it to the main actor; tests use one
/// instance per case.
public final class HistoryStore {
    private let db: OpaquePointer

    /// Pass ":memory:" for tests.
    public init(path: String) throws {
        if path != ":memory:" {
            let directory = (path as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
        var handle: OpaquePointer?
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            sqlite3_close(handle)
            throw HistoryStoreError(message: "Could not open the history database.")
        }
        db = handle
        // Fresh schema: the pre-pivot DBs were deleted with the web app, so
        // `inputs` is part of the base table (no PRAGMA-guarded migration).
        exec("""
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS runs (
            id TEXT PRIMARY KEY,
            task_path TEXT NOT NULL,
            started_at INTEGER NOT NULL,
            finished_at INTEGER NOT NULL,
            status TEXT NOT NULL,
            model TEXT NOT NULL,
            input_tokens INTEGER,
            output_tokens INTEGER,
            output TEXT,
            error TEXT,
            inputs TEXT
        );
        CREATE INDEX IF NOT EXISTS runs_by_task ON runs(task_path, started_at);
        CREATE TABLE IF NOT EXISTS snapshots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            task_path TEXT NOT NULL,
            at INTEGER NOT NULL,
            kind TEXT NOT NULL,
            content TEXT NOT NULL,
            lines_added INTEGER NOT NULL,
            lines_removed INTEGER NOT NULL,
            renamed_from TEXT
        );
        CREATE INDEX IF NOT EXISTS snapshots_by_task ON snapshots(task_path, id);
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Runs

    public func recordRun(_ record: RunRecord) {
        let statement = prepare("""
        INSERT INTO runs (id, task_path, started_at, finished_at, status, model, input_tokens, output_tokens, output, error, inputs)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """)
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, record.id)
        bind(statement, 2, record.taskPath)
        bind(statement, 3, record.startedAt)
        bind(statement, 4, record.finishedAt)
        bind(statement, 5, record.status.rawValue)
        bind(statement, 6, record.model)
        bind(statement, 7, record.inputTokens)
        bind(statement, 8, record.outputTokens)
        bind(statement, 9, record.output)
        bind(statement, 10, record.error)
        bind(statement, 11, record.inputs.flatMap(encodeInputs))
        sqlite3_step(statement)
    }

    /// Newest first.
    public func listRuns(taskPath: String) -> [RunRecord] {
        let statement = prepare("""
        SELECT id, task_path, started_at, finished_at, status, model, input_tokens, output_tokens, output, error, inputs
        FROM runs WHERE task_path = ? ORDER BY started_at DESC, id DESC
        """)
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, taskPath)
        var records: [RunRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(RunRecord(
                id: text(statement, 0) ?? "",
                taskPath: text(statement, 1) ?? "",
                startedAt: int(statement, 2) ?? 0,
                finishedAt: int(statement, 3) ?? 0,
                status: RunStatus(rawValue: text(statement, 4) ?? "") ?? .failed,
                model: text(statement, 5) ?? "",
                inputTokens: int(statement, 6),
                outputTokens: int(statement, 7),
                output: text(statement, 8),
                error: text(statement, 9),
                inputs: text(statement, 10).flatMap(decodeInputs)
            ))
        }
        return records
    }

    // MARK: - Snapshots

    /// Records a content snapshot. Change counts are diffed against the
    /// previous snapshot of the same task. No-op edits/restores (content
    /// identical to the latest snapshot) are skipped so ⌘S spam doesn't pile
    /// up entries.
    @discardableResult
    public func recordSnapshot(
        taskPath: String,
        kind: SnapshotKind,
        content: String,
        at: Int,
        renamedFrom: String? = nil
    ) -> SnapshotRecord? {
        let previous = latestContent(taskPath: taskPath)
        if (kind == .edited || kind == .restored), previous == content {
            return nil
        }
        // A rename doesn't change content, and a first snapshot is pure
        // additions — diffing against "" would count a phantom removed line.
        let (added, removed): (Int, Int)
        switch (kind, previous) {
        case (.renamed, _):
            (added, removed) = (0, 0)
        case (_, nil):
            (added, removed) = (content.components(separatedBy: "\n").count, 0)
        case (_, .some(let previous)):
            (added, removed) = diffCounts(before: previous, after: content)
        }

        let statement = prepare("""
        INSERT INTO snapshots (task_path, at, kind, content, lines_added, lines_removed, renamed_from)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """)
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, taskPath)
        bind(statement, 2, at)
        bind(statement, 3, kind.rawValue)
        bind(statement, 4, content)
        bind(statement, 5, added)
        bind(statement, 6, removed)
        bind(statement, 7, renamedFrom)
        sqlite3_step(statement)
        return SnapshotRecord(
            id: Int(sqlite3_last_insert_rowid(db)),
            taskPath: taskPath,
            at: at,
            kind: kind,
            linesAdded: added,
            linesRemoved: removed,
            renamedFrom: renamedFrom
        )
    }

    /// Newest first, without content (list entries are summaries).
    public func listSnapshots(taskPath: String) -> [SnapshotRecord] {
        let statement = prepare("""
        SELECT id, task_path, at, kind, lines_added, lines_removed, renamed_from
        FROM snapshots WHERE task_path = ? ORDER BY id DESC
        """)
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, taskPath)
        var records: [SnapshotRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            records.append(SnapshotRecord(
                id: int(statement, 0) ?? 0,
                taskPath: text(statement, 1) ?? "",
                at: int(statement, 2) ?? 0,
                kind: SnapshotKind(rawValue: text(statement, 3) ?? "") ?? .edited,
                linesAdded: int(statement, 4) ?? 0,
                linesRemoved: int(statement, 5) ?? 0,
                renamedFrom: text(statement, 6)
            ))
        }
        return records
    }

    /// One snapshot with its content and the content it replaced (for diffs).
    public func getSnapshot(id: Int) -> (record: SnapshotRecord, content: String, prevContent: String)? {
        let statement = prepare("""
        SELECT id, task_path, at, kind, lines_added, lines_removed, renamed_from, content
        FROM snapshots WHERE id = ?
        """)
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let record = SnapshotRecord(
            id: int(statement, 0) ?? 0,
            taskPath: text(statement, 1) ?? "",
            at: int(statement, 2) ?? 0,
            kind: SnapshotKind(rawValue: text(statement, 3) ?? "") ?? .edited,
            linesAdded: int(statement, 4) ?? 0,
            linesRemoved: int(statement, 5) ?? 0,
            renamedFrom: text(statement, 6)
        )
        let content = text(statement, 7) ?? ""

        let prevStatement = prepare("""
        SELECT content FROM snapshots WHERE task_path = ? AND id < ? ORDER BY id DESC LIMIT 1
        """)
        defer { sqlite3_finalize(prevStatement) }
        bind(prevStatement, 1, record.taskPath)
        bind(prevStatement, 2, record.id)
        let prevContent = sqlite3_step(prevStatement) == SQLITE_ROW ? (text(prevStatement, 0) ?? "") : ""

        return (record, content, prevContent)
    }

    // MARK: - Lifecycle

    /// Carries a task's history over to its new filename and marks the rename.
    public func renameTask(from: String, to: String, content: String, at: Int) {
        update("UPDATE runs SET task_path = ? WHERE task_path = ?", to, from)
        update("UPDATE snapshots SET task_path = ? WHERE task_path = ?", to, from)
        recordSnapshot(taskPath: to, kind: .renamed, content: content, at: at, renamedFrom: from)
    }

    /// Drops all history for a deleted task (deletes are permanent, like the file).
    public func deleteTask(taskPath: String) {
        update("DELETE FROM runs WHERE task_path = ?", taskPath)
        update("DELETE FROM snapshots WHERE task_path = ?", taskPath)
    }

    // MARK: - Internals

    private func latestContent(taskPath: String) -> String? {
        let statement = prepare("SELECT content FROM snapshots WHERE task_path = ? ORDER BY id DESC LIMIT 1")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, taskPath)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return text(statement, 0)
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func update(_ sql: String, _ first: String, _ second: String? = nil) {
        let statement = prepare(sql)
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, first)
        if let second {
            bind(statement, 2, second)
        }
        sqlite3_step(statement)
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        return statement
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(statement, index, Int64(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        sqlite3_column_text(statement, index).map { String(cString: $0) }
    }

    private func int(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, index))
    }

    private func encodeInputs(_ inputs: [String: String]) -> String? {
        (try? JSONEncoder().encode(inputs)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private func decodeInputs(_ json: String) -> [String: String]? {
        try? JSONDecoder().decode([String: String].self, from: Data(json.utf8))
    }
}
