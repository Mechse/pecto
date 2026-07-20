/// The services Pecto can run a task against.
public enum ProviderID: String, CaseIterable, Sendable, Hashable, Codable {
    case anthropic
    case openai
    case gemini
    case xai
    case apple
}

/// A provider-qualified model reference, e.g. "openai/gpt-5.1".
///
/// Task frontmatter stores the qualified form. Bare model strings (written
/// before providers existed) parse as Anthropic, so old task files keep
/// working untouched.
public struct ModelRef: Equatable, Hashable, Sendable {
    public let provider: ProviderID
    public let model: String

    public init(provider: ProviderID, model: String) {
        self.provider = provider
        self.model = model
    }

    /// Splits on the first "/". A recognized prefix picks the provider; any
    /// other string — bare or with an unknown prefix — is an Anthropic model
    /// ID taken verbatim.
    public static func parse(_ raw: String) -> ModelRef {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = trimmed.firstIndex(of: "/"),
           let provider = ProviderID(rawValue: String(trimmed[..<slash])) {
            let model = String(trimmed[trimmed.index(after: slash)...])
            if !model.isEmpty {
                return ModelRef(provider: provider, model: model)
            }
        }
        return ModelRef(provider: .anthropic, model: trimmed)
    }

    public var qualified: String { "\(provider.rawValue)/\(model)" }
}
