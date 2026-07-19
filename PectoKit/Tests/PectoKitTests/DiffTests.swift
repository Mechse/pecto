import Testing
@testable import PectoKit

@Suite struct DiffTests {
    @Test func identicalContentIsAllSame() {
        let lines = diffLines(before: "a\nb", after: "a\nb")
        #expect(lines == [DiffLine(type: .same, text: "a"), DiffLine(type: .same, text: "b")])
        #expect(diffCounts(before: "a\nb", after: "a\nb") == (0, 0))
    }

    @Test func detectsAddedAndRemovedLines() {
        let lines = diffLines(before: "a\nb\nc", after: "a\nc\nd")
        #expect(lines == [
            DiffLine(type: .same, text: "a"),
            DiffLine(type: .removed, text: "b"),
            DiffLine(type: .same, text: "c"),
            DiffLine(type: .added, text: "d"),
        ])
        let counts = diffCounts(before: "a\nb\nc", after: "a\nc\nd")
        #expect(counts.added == 1)
        #expect(counts.removed == 1)
    }

    @Test func changedLineIsRemovePlusAdd() {
        let counts = diffCounts(before: "hello world", after: "hello swift")
        #expect(counts.added == 1)
        #expect(counts.removed == 1)
    }

    @Test func emptySidesDiffAgainstOneEmptyLine() {
        // "".components(separatedBy:) is [""], matching JS "".split("\n").
        let lines = diffLines(before: "", after: "a")
        #expect(lines == [DiffLine(type: .removed, text: ""), DiffLine(type: .added, text: "a")])
    }
}
