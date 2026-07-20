import Foundation

/// Direct, non-streaming call to an OpenAI-style chat-completions API — no
/// SDK. Serves both OpenAI and xAI, which share the wire format.
public struct OpenAICompatibleClient: ModelProviderClient, Sendable {
    public let id: ProviderID
    let providerName: String
    let session: URLSession
    let baseURL: URL
    /// Newer OpenAI models reject `max_tokens` in favor of
    /// `max_completion_tokens`; xAI documents `max_tokens`.
    let maxTokensField: String

    public static func openAI(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.openai.com")!
    ) -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            id: .openai,
            providerName: "OpenAI",
            session: session,
            baseURL: baseURL,
            maxTokensField: "max_completion_tokens"
        )
    }

    public static func xAI(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.x.ai")!
    ) -> OpenAICompatibleClient {
        OpenAICompatibleClient(
            id: .xai,
            providerName: "xAI",
            session: session,
            baseURL: baseURL,
            maxTokensField: "max_tokens"
        )
    }

    public func run(prompt: RunPrompt, apiKey: String?, model: String) async throws -> RunOutput {
        guard let apiKey else {
            throw RunError("Add your \(providerName) API key in Pecto's Settings first.")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "model": model,
            maxTokensField: ProviderCatalog.maxTokens,
            "messages": [
                ["role": "system", "content": prompt.system],
                ["role": "user", "content": prompt.user],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let decoded = try? JSONDecoder().decode(ChatCompletionsResponse.self, from: data) else {
            throw RunError("The \(providerName) API sent a response Pecto couldn't read.")
        }
        return RunOutput(
            text: decoded.choices.first?.message.content ?? "",
            usage: RunUsage(
                inputTokens: decoded.usage?.promptTokens,
                outputTokens: decoded.usage?.completionTokens
            )
        )
    }

    public func validateKey(_ apiKey: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/models"))
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RunError("Couldn't reach the \(providerName) API. Check your internet connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 {
                throw RunError("\(providerName) rejected the API key. Check it in Pecto's Settings.")
            }
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw RunError(envelope.error.message)
            }
            throw RunError("The \(providerName) API returned an error (HTTP \(status)).")
        }
        return data
    }
}

struct ChatCompletionsResponse: Decodable, Sendable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable, Sendable {
        let message: Message
    }

    struct Message: Decodable, Sendable {
        let content: String?
    }

    struct Usage: Decodable, Sendable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}
