import Foundation

/// A run failure with a message fit for a notification.
public struct RunError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public struct MessagesRequest: Encodable, Sendable {
    public let model: String
    public let maxTokens: Int
    public let system: String
    public let messages: [ChatMessage]

    public struct ChatMessage: Encodable, Sendable {
        public let role: String
        public let content: String
    }

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
    }
}

public struct MessagesResponse: Decodable, Sendable {
    public let content: [ContentBlock]
    public let stopReason: String?
    public let usage: Usage?

    public struct ContentBlock: Decodable, Sendable {
        public let type: String
        public let text: String?
    }

    public struct Usage: Decodable, Sendable {
        public let inputTokens: Int?
        public let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case usage
    }

    public var text: String {
        content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
    }
}

public struct RunUsage: Equatable, Sendable {
    public let inputTokens: Int?
    public let outputTokens: Int?

    public init(inputTokens: Int?, outputTokens: Int?) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public struct RunOutput: Equatable, Sendable {
    public let text: String
    public let usage: RunUsage

    public init(text: String, usage: RunUsage) {
        self.text = text
        self.usage = usage
    }
}

struct APIErrorEnvelope: Decodable {
    let error: Detail

    struct Detail: Decodable {
        let type: String
        let message: String
    }
}

/// Direct, non-streaming call to the Anthropic Messages API — no SDK.
public struct AnthropicClient: ModelProviderClient, Sendable {
    public let id: ProviderID = .anthropic

    let session: URLSession
    let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://api.anthropic.com")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func run(
        prompt: RunPrompt,
        apiKey: String?,
        model: String = ProviderCatalog.info(for: .anthropic).defaultModel
    ) async throws -> RunOutput {
        guard let apiKey else {
            throw RunError("Add your Anthropic API key in Pecto's Settings first.")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/messages"))
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONEncoder().encode(
            MessagesRequest(
                model: model,
                maxTokens: ProviderCatalog.maxTokens,
                system: prompt.system,
                messages: [.init(role: "user", content: prompt.user)]
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RunError("Couldn't reach the Anthropic API. Check your internet connection and try again.")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 {
                throw RunError("Anthropic rejected the API key. Check it in Pecto's Settings.")
            }
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw RunError(envelope.error.message)
            }
            throw RunError("The Anthropic API returned an error (HTTP \(status)).")
        }

        guard let decoded = try? JSONDecoder().decode(MessagesResponse.self, from: data) else {
            throw RunError("The Anthropic API sent a response Pecto couldn't read.")
        }
        return RunOutput(
            text: decoded.text,
            usage: RunUsage(
                inputTokens: decoded.usage?.inputTokens,
                outputTokens: decoded.usage?.outputTokens
            )
        )
    }

    public func validateKey(_ apiKey: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/models"))
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw RunError("Couldn't reach the Anthropic API. Check your internet connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 || status == 403 {
                throw RunError("Anthropic rejected the API key. Check it in Pecto's Settings.")
            }
            throw RunError("The Anthropic API returned an error (HTTP \(status)).")
        }
    }
}
