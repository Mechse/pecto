import Foundation
import Yams

public struct TaskFrontmatter: Equatable, Sendable {
    public var name: String
    public var description: String
    /// Anthropic model ID override; nil means the app default.
    public var model: String?

    public init(name: String, description: String, model: String? = nil) {
        self.name = name
        self.description = description
        self.model = model
    }
}

public struct ParsedTask: Equatable, Sendable {
    public let frontmatter: TaskFrontmatter
    /// The natural-language body of the task file, trimmed.
    public let instructions: String
    /// The original file content, verbatim.
    public let raw: String

    public init(frontmatter: TaskFrontmatter, instructions: String, raw: String) {
        self.frontmatter = frontmatter
        self.instructions = instructions
        self.raw = raw
    }
}

/// A task-file problem, phrased for non-technical users. The wording is part
/// of the product surface — surfaced verbatim in the editor and notifications.
public struct TaskParseError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Shared by frontmatter `name:` and on-disk file names (minus `.md`).
public let taskSlugPattern = "^[a-z0-9][a-z0-9-]*$"

public func isTaskSlug(_ value: String) -> Bool {
    value.range(of: taskSlugPattern, options: .regularExpression) != nil
}

let frontmatterRegex = try! NSRegularExpression(
    pattern: "^---\\r?\\n([\\s\\S]*?)\\r?\\n---\\r?\\n?([\\s\\S]*)$"
)

public func parseTask(_ markdown: String) throws -> ParsedTask {
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

    let data: Any?
    do {
        data = try Yams.load(yaml: String(trimmed[yamlRange]))
    } catch {
        throw TaskParseError(
            "The settings block at the top of this task could not be read. Check it for stray characters or broken indentation."
        )
    }

    let frontmatter = try validateFrontmatter(data)

    let instructions = String(trimmed[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    if instructions.isEmpty {
        throw TaskParseError(
            "This task has settings but no instructions. Below the settings block, describe in plain language what should happen."
        )
    }

    return ParsedTask(frontmatter: frontmatter, instructions: instructions, raw: markdown)
}

func validateFrontmatter(_ data: Any?) throws -> TaskFrontmatter {
    let fields: [AnyHashable: Any]
    switch data {
    case nil:
        fields = [:]
    case let mapping as [AnyHashable: Any]:
        fields = mapping
    default:
        throw TaskParseError("The task settings are incomplete.")
    }
    // Unknown keys are deliberately ignored so future fields (model:, inputs:, …)
    // don't break older apps.
    guard let name = fields["name"] as? String, !name.isEmpty else {
        throw TaskParseError("Every task needs a name (name)")
    }
    guard isTaskSlug(name) else {
        throw TaskParseError(
            "Task names use lowercase letters, numbers and dashes (e.g. enrich-new-signups) (name)"
        )
    }
    guard let description = fields["description"] as? String, !description.isEmpty else {
        throw TaskParseError("Every task needs a one-line description (description)")
    }
    var model: String?
    if let rawModel = fields["model"] {
        guard let value = rawModel as? String, !value.isEmpty else {
            throw TaskParseError(
                "The model setting must be a model name like claude-sonnet-4-5 (model)"
            )
        }
        model = value
    }
    return TaskFrontmatter(name: name, description: description, model: model)
}
