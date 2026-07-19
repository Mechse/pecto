/// Content written for a freshly created task — must parse and run as-is.
public func newTaskTemplate(name: String) -> String {
    """
    ---
    name: \(name)
    description: Describe what this task does in one line.
    ---

    Write plain-language instructions for what should happen when this task runs.

    """
}
