import Foundation
import Testing
@testable import PectoKit

private func makeClient() -> AnthropicClient {
    AnthropicClient(session: mockedSession())
}

private func setHandler(_ handler: MockURLProtocol.Handler?) {
    MockURLProtocol.setHandler(forHost: "api.anthropic.com", handler)
}

private let prompt = RunPrompt(system: "You are executing the task.", user: "Improve this: my draft")

@Suite(.serialized) struct AnthropicClientTests {
    @Test func sendsWellFormedRequestAndConcatenatesTextBlocks() async throws {
        setHandler { request, body in
            #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")

            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(json?["model"] as? String == "claude-sonnet-4-5")
            #expect(json?["max_tokens"] as? Int == 8192)
            #expect(json?["system"] as? String == "You are executing the task.")
            let messages = json?["messages"] as? [[String: Any]]
            #expect(messages?.count == 1)
            #expect(messages?[0]["role"] as? String == "user")
            #expect(messages?[0]["content"] as? String == "Improve this: my draft")

            let response = """
            {"content": [{"type": "text", "text": "Part one. "}, {"type": "tool_use", "id": "x"}, {"type": "text", "text": "Part two."}], "stop_reason": "end_turn", "usage": {"input_tokens": 89, "output_tokens": 35}}
            """
            return (200, Data(response.utf8))
        }
        let output = try await makeClient().run(prompt: prompt, apiKey: "sk-test")
        #expect(output.text == "Part one. Part two.")
        #expect(output.usage == RunUsage(inputTokens: 89, outputTokens: 35))
    }

    @Test func toleratesMissingUsage() async throws {
        setHandler { _, _ in
            (200, Data(#"{"content": [{"type": "text", "text": "hi"}]}"#.utf8))
        }
        let output = try await makeClient().run(prompt: prompt, apiKey: "sk-test")
        #expect(output.usage == RunUsage(inputTokens: nil, outputTokens: nil))
    }

    @Test func surfacesAPIErrorMessages() async {
        setHandler { _, _ in
            (429, Data(#"{"error": {"type": "rate_limit_error", "message": "Rate limited, slow down."}}"#.utf8))
        }
        let message = await runErrorMessage { try await makeClient().run(prompt: prompt, apiKey: "sk-test") }
        #expect(message == "Rate limited, slow down.")
    }

    @Test func mapsUnauthorizedToSettingsHint() async {
        setHandler { _, _ in
            (401, Data(#"{"error": {"type": "authentication_error", "message": "invalid x-api-key"}}"#.utf8))
        }
        let message = await runErrorMessage { try await makeClient().run(prompt: prompt, apiKey: "bad") }
        #expect(message == "Anthropic rejected the API key. Check it in Pecto's Settings.")
    }

    @Test func fallsBackOnUnreadableErrorBody() async {
        setHandler { _, _ in (500, Data("<html>oops</html>".utf8)) }
        let message = await runErrorMessage { try await makeClient().run(prompt: prompt, apiKey: "sk-test") }
        #expect(message == "The Anthropic API returned an error (HTTP 500).")
    }

    @Test func mapsNetworkFailuresToFriendlyMessage() async {
        setHandler { _, _ in throw URLError(.notConnectedToInternet) }
        let message = await runErrorMessage { try await makeClient().run(prompt: prompt, apiKey: "sk-test") }
        #expect(message == "Couldn't reach the Anthropic API. Check your internet connection and try again.")
    }

    @Test func rejectsMissingKeyBeforeAnyRequest() async {
        setHandler { _, _ in
            Issue.record("no request should be sent without a key")
            return (200, Data())
        }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: nil, model: "claude-sonnet-5")
        }
        #expect(message == "Add your Anthropic API key in Pecto's Settings first.")
    }

    @Test func validateKeyHitsModelsEndpoint() async throws {
        setHandler { request, _ in
            #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/models")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
            return (200, Data(#"{"data": []}"#.utf8))
        }
        try await makeClient().validateKey("sk-test")
    }

    @Test func validateKeyMapsUnauthorized() async {
        setHandler { _, _ in (401, Data()) }
        let message = await runErrorMessage { try await makeClient().validateKey("bad") }
        #expect(message == "Anthropic rejected the API key. Check it in Pecto's Settings.")
    }
}
