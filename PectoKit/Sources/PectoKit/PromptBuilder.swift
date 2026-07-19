public struct RunPrompt: Equatable, Sendable {
    public let system: String
    public let user: String

    public init(system: String, user: String) {
        self.system = system
        self.user = user
    }
}

public func buildPrompt(task: TaskFrontmatter, filledInstructions: String) -> RunPrompt {
    let system = """
    You are executing the task "\(task.name)": \(task.description).
    Follow the instructions exactly. Reply with only the final result of the task — no preamble.
    """
    return RunPrompt(system: system, user: filledInstructions)
}
