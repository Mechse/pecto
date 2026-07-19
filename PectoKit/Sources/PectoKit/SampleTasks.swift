/// Starter tasks seeded into a fresh workspace. Kept in sync with the
/// repo's `workspace/` samples.
public enum SampleTasks {
    public static let all: [(fileName: String, content: String)] = [
        ("improve-email.md", improveEmail),
        ("summarize-text.md", summarizeText),
    ]

    static let improveEmail = """
    ---
    name: improve-email
    description: Polish an email draft without losing the sender's voice.
    ---

    Improve the email draft below. Fix grammar and spelling, tighten the wording, and make the tone friendly and professional — but keep the sender's voice and don't change what the email is saying. Keep roughly the same length. If the draft has no subject line, add a short one.

    Reply with only the improved email.

    {{clipboard}}

    """

    static let summarizeText = """
    ---
    name: summarize-text
    description: Boil any text down to three bullet points
    ---

    Summarize the following text in three bullet points:
    {{clipboard}}

    """
}
