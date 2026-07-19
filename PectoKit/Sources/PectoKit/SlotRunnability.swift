public enum SlotRunnability: Equatable, Sendable {
    case runnable(needsClipboard: Bool)
    case notRunnable(reason: String)
}

/// A task can run from a shortcut slot only if its placeholders are exactly
/// none or `{{clipboard}}` — the clipboard is the single input a slot can fill.
public func slotRunnability(instructions: String) -> SlotRunnability {
    let names = extractPlaceholders(instructions)
    if names.isEmpty {
        return .runnable(needsClipboard: false)
    }
    if names == ["clipboard"] {
        return .runnable(needsClipboard: true)
    }
    let foreign = names.filter { $0 != "clipboard" }.map { "{{\($0)}}" }.joined(separator: ", ")
    return .notRunnable(
        reason: "This task asks for \(foreign), but a shortcut can only fill {{clipboard}}. Rewrite it to use {{clipboard}} as its single input."
    )
}
