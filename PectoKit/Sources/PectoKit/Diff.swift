public struct DiffLine: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case same, added, removed
    }

    public let type: Kind
    public let text: String

    public init(type: Kind, text: String) {
        self.type = type
        self.text = text
    }
}

/// Line-based LCS diff. Task files are small, so the O(n·m) table is fine —
/// shared by the change summaries and the history pane's diff view.
public func diffLines(before: String, after: String) -> [DiffLine] {
    let a = before.components(separatedBy: "\n")
    let b = after.components(separatedBy: "\n")
    let m = a.count
    let n = b.count
    var lcs = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
    for i in stride(from: m - 1, through: 0, by: -1) {
        for j in stride(from: n - 1, through: 0, by: -1) {
            lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
        }
    }
    var out: [DiffLine] = []
    var i = 0
    var j = 0
    while i < m, j < n {
        if a[i] == b[j] {
            out.append(DiffLine(type: .same, text: a[i]))
            i += 1
            j += 1
        } else if lcs[i + 1][j] >= lcs[i][j + 1] {
            out.append(DiffLine(type: .removed, text: a[i]))
            i += 1
        } else {
            out.append(DiffLine(type: .added, text: b[j]))
            j += 1
        }
    }
    while i < m {
        out.append(DiffLine(type: .removed, text: a[i]))
        i += 1
    }
    while j < n {
        out.append(DiffLine(type: .added, text: b[j]))
        j += 1
    }
    return out
}

/// Added/removed line counts between two versions.
public func diffCounts(before: String, after: String) -> (added: Int, removed: Int) {
    var added = 0
    var removed = 0
    for line in diffLines(before: before, after: after) {
        switch line.type {
        case .added: added += 1
        case .removed: removed += 1
        case .same: break
        }
    }
    return (added, removed)
}
