import Foundation

/// Direct, non-streaming call to the Gemini generateContent API — no SDK.
public struct GeminiClient: ModelProviderClient, Sendable {
    public let id: ProviderID = .gemini

    let session: URLSession
    let baseURL: URL

    public init(
        session: URLSession = .shared,
        baseURL: URL = URL(string: "https://generativelanguage.googleapis.com")!
    ) {
        self.session = session
        self.baseURL = baseURL
    }

    public func run(prompt: RunPrompt, apiKey: String?, model: String) async throws -> RunOutput {
        guard let apiKey else {
            throw RunError("Add your Google Gemini API key in Pecto's Settings first.")
        }
        var request = URLRequest(
            url: baseURL.appendingPathComponent("v1beta/models/\(model):generateContent")
        )
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let body: [String: Any] = [
            "system_instruction": ["parts": [["text": prompt.system]]],
            "contents": [["role": "user", "parts": [["text": prompt.user]]]],
            "generationConfig": ["maxOutputTokens": ProviderCatalog.maxTokens],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await send(request)
        guard let decoded = try? JSONDecoder().decode(GenerateContentResponse.self, from: data) else {
            throw RunError("The Google Gemini API sent a response Pecto couldn't read.")
        }
        // Safety blocks come back as HTTP 200 with no candidates — surface
        // the reason instead of an inexplicable empty result.
        guard let candidate = decoded.candidates?.first else {
            if let reason = decoded.promptFeedback?.blockReason {
                throw RunError("Gemini declined this prompt (\(reason)). Your clipboard is unchanged.")
            }
            throw RunError("Gemini returned no result for this prompt.")
        }
        let text = (candidate.content?.parts ?? []).compactMap(\.text).joined()
        return RunOutput(
            text: text,
            usage: RunUsage(
                inputTokens: decoded.usageMetadata?.promptTokenCount,
                outputTokens: decoded.usageMetadata?.candidatesTokenCount
            )
        )
    }

    public func validateKey(_ apiKey: String) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1beta/models"))
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        _ = try await send(request)
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw RunError("Couldn't reach the Google Gemini API. Check your internet connection and try again.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            // Google rejects bad keys with 400 (API_KEY_INVALID) as well as
            // 401/403 — treat all of them as a key problem.
            let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data)
            if status == 401 || status == 403 || envelope?.isInvalidKey == true {
                throw RunError("Google Gemini rejected the API key. Check it in Pecto's Settings.")
            }
            if let message = envelope?.error.message {
                throw RunError(message)
            }
            throw RunError("The Google Gemini API returned an error (HTTP \(status)).")
        }
        return data
    }
}

struct GenerateContentResponse: Decodable, Sendable {
    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let usageMetadata: UsageMetadata?

    struct Candidate: Decodable, Sendable {
        let content: Content?
    }

    struct Content: Decodable, Sendable {
        let parts: [Part]?
    }

    struct Part: Decodable, Sendable {
        let text: String?
    }

    struct PromptFeedback: Decodable, Sendable {
        let blockReason: String?
    }

    struct UsageMetadata: Decodable, Sendable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }
}

struct GeminiErrorEnvelope: Decodable {
    let error: Detail

    struct Detail: Decodable {
        let message: String?
        let status: String?
        let details: [Item]?

        struct Item: Decodable {
            let reason: String?
        }
    }

    var isInvalidKey: Bool {
        error.details?.contains { $0.reason == "API_KEY_INVALID" } ?? false
    }
}
