/// Description written into new and repaired tasks until the user sets one.
public let placeholderDescription = "Describe what this task does in one line."

/// Content written for a freshly created task — must parse and run as-is.
public func newTaskTemplate(name: String) -> String {
    """
    ---
    name: \(name)
    description: \(placeholderDescription)
    ---

    Write plain-language instructions for what should happen when this task runs.

    """
}
