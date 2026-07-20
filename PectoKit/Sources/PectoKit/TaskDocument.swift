import Foundation
import Yams

/// A task file split into its hidden settings (frontmatter) and the editable
/// body. The editor binds to `body` only; frontmatter is round-tripped through
/// `serialize()` so the user never sees or breaks the YAML block.
public struct TaskDocument: Equatable, Sendable {
    public var frontmatter: TaskFrontmatter
    /// Frontmatter lines this app doesn't understand (unknown keys and their
    /// continuations, comments), preserved verbatim so forward-compatible
    /// fields written by newer apps survive a round-trip.
    public var extraFrontmatterLines: [String]
    /// Instructions below the settings block, trimmed of surrounding whitespace.
    public var body: String

    public init(frontmatter: TaskFrontmatter, extraFrontmatterLines: [String] = [], body: String) {
        self.frontmatter = frontmatter
        self.extraFrontmatterLines = extraFrontmatterLines
        self.body = body
    }

    /// Deterministic emitter: fixed key order, stable quoting. The same
    /// document always serializes to the same bytes, so no-op saves don't
    /// produce noisy diffs. Yams' emitter is avoided on purpose — its line
    /// folding and quoting choices are not stable enough for that guarantee.
    public func serialize() -> String {
        var lines = ["---"]
        lines.append("name: \(Self.yamlScalar(frontmatter.name))")
        lines.append("description: \(Self.yamlScalar(frontmatter.description))")
        if let model = frontmatter.model {
            lines.append("model: \(Self.yamlScalar(model))")
        }
        lines.append(contentsOf: extraFrontmatterLines)
        lines.append("---")
        var result = lines.joined(separator: "\n") + "\n"
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBody.isEmpty {
            result += "\n" + trimmedBody + "\n"
        }
        return result
    }

    /// Plain when unambiguous, double-quoted (JSON-style escapes) otherwise.
    /// Quoting is triggered by anything YAML could reinterpret: indicators,
    /// `:`/`#`, numeric or boolean look-alikes, surrounding whitespace.
    static func yamlScalar(_ value: String) -> String {
        let safePlain = "^[A-Za-z][A-Za-z0-9 ._,()/'!?-]*$"
        let booleanWords: Set<String> = ["true", "false", "yes", "no", "on", "off", "null"]
        if value.range(of: safePlain, options: .regularExpression) != nil,
           !value.hasSuffix(" "),
           !booleanWords.contains(value.lowercased()) {
            return value
        }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}

private let knownFrontmatterKeys: Set<String> = ["name", "description", "model"]

/// Strict split of a task file into frontmatter + body. Unlike `parseTask`,
/// an empty body is allowed — the editor legitimately holds an empty draft.
public func parseDocument(_ markdown: String) throws -> TaskDocument {
    let trimmed = String(markdown.drop(while: \.isWhitespace))
    let searchRange = NSRange(trimmed.startIndex..., in: trimmed)
    guard
        let match = frontmatterRegex.firstMatch(in: trimmed, options: [], range: searchRange),
        let yamlRange = Range(match.range(at: 1), in: trimmed),
        let bodyRange = Range(match.range(at: 2), in: trimmed)
    else {
        throw TaskParseError(
            "This file is missing its settings block. A task starts with a section between two '---' lines that names the task and describes what it needs."
        )
    }

    let yamlText = String(trimmed[yamlRange])
    let data: Any?
    do {
        data = try Yams.load(yaml: yamlText)
    } catch {
        throw TaskParseError(
            "The settings block at the top of this task could not be read. Check it for stray characters or broken indentation."
        )
    }
    let frontmatter = try validateFrontmatter(data)

    let body = String(trimmed[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    return TaskDocument(
        frontmatter: frontmatter,
        extraFrontmatterLines: extraLines(inYAML: yamlText),
        body: body
    )
}

/// Collects the frontmatter lines that don't belong to a known key: unknown
/// top-level keys with their indented continuations, and comments. Known keys'
/// values are re-emitted from the validated struct, so their lines are dropped.
private func extraLines(inYAML yamlText: String) -> [String] {
    var extras: [String] = []
    var ownerIsKnown = false
    for line in yamlText.components(separatedBy: "\n") {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        if stripped.hasPrefix("#") {
            extras.append(line)
            continue
        }
        let isTopLevelKey = !line.hasPrefix(" ") && !line.hasPrefix("\t")
            && line.range(of: "^[A-Za-z0-9_-]+:", options: .regularExpression) != nil
        if isTopLevelKey {
            let key = String(line[..<line.firstIndex(of: ":")!])
            ownerIsKnown = knownFrontmatterKeys.contains(key)
        }
        if !ownerIsKnown {
            extras.append(line)
        }
    }
    // Trailing blank lines are formatting noise, not data.
    while let last = extras.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
        extras.removeLast()
    }
    return extras
}

/// Lenient load for the editor: any parse failure yields a repaired document
/// (name from the filename, placeholder description) whose valid frontmatter
/// reaches disk on the next save. The user never has to fix YAML by hand.
public func loadDocumentRepairing(
    _ markdown: String, fallbackName: String
) -> (document: TaskDocument, wasRepaired: Bool) {
    if let document = try? parseDocument(markdown) {
        return (document, false)
    }
    let name = isTaskSlug(fallbackName) ? fallbackName : "task"
    // If a fence block exists but its YAML is broken, keep only the
    // instructions below it — the broken settings are replaced, not shown.
    let trimmed = String(markdown.drop(while: \.isWhitespace))
    let searchRange = NSRange(trimmed.startIndex..., in: trimmed)
    var body = trimmed
    if let match = frontmatterRegex.firstMatch(in: trimmed, options: [], range: searchRange),
       let bodyRange = Range(match.range(at: 2), in: trimmed) {
        body = String(trimmed[bodyRange])
    }
    let document = TaskDocument(
        frontmatter: TaskFrontmatter(name: name, description: placeholderDescription),
        extraFrontmatterLines: [],
        body: body.trimmingCharacters(in: .whitespacesAndNewlines)
    )
    return (document, true)
}
