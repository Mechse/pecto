import Foundation

public enum RunStatus: String, Sendable {
    case succeeded, failed
}

/// A finished run, as persisted in the history store.
public struct RunRecord: Equatable, Sendable, Identifiable {
    public let id: String
    public let taskPath: String
    /// Milliseconds since the epoch (matches the legacy web-app store).
    public let startedAt: Int
    public let finishedAt: Int
    public let status: RunStatus
    public let model: String
    public let inputTokens: Int?
    public let outputTokens: Int?
    /// Final text output (succeeded runs).
    public let output: String?
    /// Error message (failed runs).
    public let error: String?
    /// Placeholder values the run was started with, if the task takes any.
    public let inputs: [String: String]?

    public init(
        id: String,
        taskPath: String,
        startedAt: Int,
        finishedAt: Int,
        status: RunStatus,
        model: String,
        inputTokens: Int?,
        outputTokens: Int?,
        output: String?,
        error: String?,
        inputs: [String: String]?
    ) {
        self.id = id
        self.taskPath = taskPath
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.status = status
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.output = output
        self.error = error
        self.inputs = inputs
    }
}

public enum SnapshotKind: String, Sendable {
    case created, edited, renamed, restored
}

/// One entry in a task's change history. Content lives in the store; list
/// entries carry only the summary.
public struct SnapshotRecord: Equatable, Sendable, Identifiable {
    public let id: Int
    public let taskPath: String
    public let at: Int
    public let kind: SnapshotKind
    public let linesAdded: Int
    public let linesRemoved: Int
    /// Previous filename, for kind `renamed`.
    public let renamedFrom: String?

    public init(id: Int, taskPath: String, at: Int, kind: SnapshotKind, linesAdded: Int, linesRemoved: Int, renamedFrom: String?) {
        self.id = id
        self.taskPath = taskPath
        self.at = at
        self.kind = kind
        self.linesAdded = linesAdded
        self.linesRemoved = linesRemoved
        self.renamedFrom = renamedFrom
    }
}
