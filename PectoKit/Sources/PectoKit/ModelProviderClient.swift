import Foundation

/// One model service Pecto can run a prompt against. Implementations are
/// stateless value types; errors surface as `RunError` with messages fit for
/// a notification.
public protocol ModelProviderClient: Sendable {
    var id: ProviderID { get }

    /// `apiKey` is nil only for key-less providers (Apple on-device).
    func run(prompt: RunPrompt, apiKey: String?, model: String) async throws -> RunOutput

    /// Cheap credential check backing the Settings "Test" button — a
    /// list-models call where the API offers one. Throws `RunError` when the
    /// key is rejected or the service can't be reached.
    func validateKey(_ apiKey: String) async throws
}

/// The clients available to a run, one per provider.
public struct ProviderRegistry: Sendable {
    private let clients: [ProviderID: any ModelProviderClient]

    public init(clients: [any ModelProviderClient]) {
        self.clients = Dictionary(uniqueKeysWithValues: clients.map { ($0.id, $0) })
    }

    public func client(for id: ProviderID) -> (any ModelProviderClient)? {
        clients[id]
    }

    /// The REST providers. The app appends the Apple on-device client, which
    /// lives in the app target because it needs the FoundationModels SDK.
    public static func standard(session: URLSession = .shared) -> ProviderRegistry {
        ProviderRegistry(clients: [
            AnthropicClient(session: session),
            OpenAICompatibleClient.openAI(session: session),
            OpenAICompatibleClient.xAI(session: session),
            GeminiClient(session: session),
        ])
    }
}
