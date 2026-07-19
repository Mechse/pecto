import Foundation

private let placeholderRegex = try! NSRegularExpression(
    pattern: "\\{\\{\\s*([a-zA-Z][a-zA-Z0-9_-]*)\\s*\\}\\}"
)

/// Placeholder names in order of first appearance, deduplicated.
public func extractPlaceholders(_ instructions: String) -> [String] {
    var names: [String] = []
    let searchRange = NSRange(instructions.startIndex..., in: instructions)
    for match in placeholderRegex.matches(in: instructions, range: searchRange) {
        guard let nameRange = Range(match.range(at: 1), in: instructions) else { continue }
        let name = String(instructions[nameRange])
        if !names.contains(name) {
            names.append(name)
        }
    }
    return names
}

/// `email_draft` → "Email draft" (only the first character is uppercased).
public func placeholderLabel(_ name: String) -> String {
    let spaced = name
        .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    guard let first = spaced.first else { return spaced }
    return first.uppercased() + spaced.dropFirst()
}

/// Single left-to-right pass: known names are substituted, unknown ones stay
/// verbatim, and substituted values are never re-scanned for placeholders.
public func fillPlaceholders(_ instructions: String, values: [String: String]) -> String {
    let searchRange = NSRange(instructions.startIndex..., in: instructions)
    var result = ""
    var cursor = instructions.startIndex
    for match in placeholderRegex.matches(in: instructions, range: searchRange) {
        guard
            let fullRange = Range(match.range, in: instructions),
            let nameRange = Range(match.range(at: 1), in: instructions)
        else { continue }
        result += instructions[cursor..<fullRange.lowerBound]
        let name = String(instructions[nameRange])
        if let value = values[name] {
            result += value
        } else {
            result += instructions[fullRange]
        }
        cursor = fullRange.upperBound
    }
    result += instructions[cursor...]
    return result
}
