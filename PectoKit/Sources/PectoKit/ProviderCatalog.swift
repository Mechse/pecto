/// Static facts about one provider: how it appears in UI and which models
/// Pecto offers in pickers. A task file may carry any model string; unknown
/// ones are still honored.
public struct ProviderInfo: Sendable, Identifiable {
    public let id: ProviderID
    public let displayName: String
    public let requiresAPIKey: Bool
    public let keyPlaceholder: String
    public let defaultModel: String
    public let selectableModels: [String]
}

public enum ProviderCatalog {
    /// Fixed order for pickers and the API-keys settings list.
    public static let all: [ProviderInfo] = [
        ProviderInfo(
            id: .anthropic,
            displayName: "Anthropic",
            requiresAPIKey: true,
            keyPlaceholder: "sk-ant-…",
            defaultModel: "claude-sonnet-4-5",
            selectableModels: ["claude-opus-4-8", "claude-sonnet-5", "claude-haiku-4-5"]
        ),
        ProviderInfo(
            id: .openai,
            displayName: "OpenAI",
            requiresAPIKey: true,
            keyPlaceholder: "sk-…",
            defaultModel: "gpt-5.1",
            selectableModels: ["gpt-5.1", "gpt-5.1-mini", "gpt-5-nano"]
        ),
        ProviderInfo(
            id: .gemini,
            displayName: "Google Gemini",
            requiresAPIKey: true,
            keyPlaceholder: "AIza…",
            defaultModel: "gemini-2.5-flash",
            selectableModels: ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite"]
        ),
        ProviderInfo(
            id: .xai,
            displayName: "xAI",
            requiresAPIKey: true,
            keyPlaceholder: "xai-…",
            defaultModel: "grok-4",
            selectableModels: ["grok-4", "grok-4-fast", "grok-3-mini"]
        ),
        ProviderInfo(
            id: .apple,
            displayName: "Apple On-Device",
            requiresAPIKey: false,
            keyPlaceholder: "",
            defaultModel: "on-device",
            selectableModels: ["on-device"]
        ),
    ]

    public static func info(for id: ProviderID) -> ProviderInfo {
        all.first { $0.id == id }!
    }

    public static let maxTokens = 8192
}
