import Foundation
import Testing
@testable import PectoKit

private let prompt = RunPrompt(system: "You are executing the task.", user: "Improve this: my draft")

@Suite(.serialized) struct OpenAIClientTests {
    private func makeClient() -> OpenAICompatibleClient {
        .openAI(session: mockedSession())
    }

    private func setHandler(_ handler: MockURLProtocol.Handler?) {
        MockURLProtocol.setHandler(forHost: "api.openai.com", handler)
    }

    @Test func sendsWellFormedRequestAndDecodesResult() async throws {
        setHandler { request, body in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            #expect(request.value(forHTTPHeaderField: "content-type") == "application/json")

            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(json?["model"] as? String == "gpt-5.1")
            #expect(json?["max_completion_tokens"] as? Int == 8192)
            #expect(json?["max_tokens"] == nil)
            let messages = json?["messages"] as? [[String: Any]]
            #expect(messages?.count == 2)
            #expect(messages?[0]["role"] as? String == "system")
            #expect(messages?[0]["content"] as? String == "You are executing the task.")
            #expect(messages?[1]["role"] as? String == "user")
            #expect(messages?[1]["content"] as? String == "Improve this: my draft")

            let response = """
            {"choices": [{"message": {"role": "assistant", "content": "Result text."}}], "usage": {"prompt_tokens": 40, "completion_tokens": 12}}
            """
            return (200, Data(response.utf8))
        }
        let output = try await makeClient().run(prompt: prompt, apiKey: "sk-test", model: "gpt-5.1")
        #expect(output.text == "Result text.")
        #expect(output.usage == RunUsage(inputTokens: 40, outputTokens: 12))
    }

    @Test func toleratesMissingUsage() async throws {
        setHandler { _, _ in
            (200, Data(#"{"choices": [{"message": {"content": "hi"}}]}"#.utf8))
        }
        let output = try await makeClient().run(prompt: prompt, apiKey: "sk-test", model: "gpt-5.1")
        #expect(output.usage == RunUsage(inputTokens: nil, outputTokens: nil))
    }

    @Test func surfacesAPIErrorMessages() async {
        setHandler { _, _ in
            (429, Data(#"{"error": {"type": "rate_limit_error", "message": "Rate limited, slow down."}}"#.utf8))
        }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: "sk-test", model: "gpt-5.1")
        }
        #expect(message == "Rate limited, slow down.")
    }

    @Test func mapsUnauthorizedToSettingsHint() async {
        setHandler { _, _ in (401, Data()) }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: "bad", model: "gpt-5.1")
        }
        #expect(message == "OpenAI rejected the API key. Check it in Pecto's Settings.")
    }

    @Test func mapsNetworkFailuresToFriendlyMessage() async {
        setHandler { _, _ in throw URLError(.notConnectedToInternet) }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: "sk-test", model: "gpt-5.1")
        }
        #expect(message == "Couldn't reach the OpenAI API. Check your internet connection and try again.")
    }

    @Test func rejectsMissingKeyBeforeAnyRequest() async {
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: nil, model: "gpt-5.1")
        }
        #expect(message == "Add your OpenAI API key in Pecto's Settings first.")
    }

    @Test func validateKeyHitsModelsEndpoint() async throws {
        setHandler { request, _ in
            #expect(request.url?.absoluteString == "https://api.openai.com/v1/models")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            return (200, Data(#"{"data": []}"#.utf8))
        }
        try await makeClient().validateKey("sk-test")
    }
}

@Suite(.serialized) struct XAIClientTests {
    private func makeClient() -> OpenAICompatibleClient {
        .xAI(session: mockedSession())
    }

    private func setHandler(_ handler: MockURLProtocol.Handler?) {
        MockURLProtocol.setHandler(forHost: "api.x.ai", handler)
    }

    @Test func targetsXAIHostAndUsesMaxTokens() async throws {
        setHandler { request, body in
            #expect(request.url?.absoluteString == "https://api.x.ai/v1/chat/completions")
            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(json?["max_tokens"] as? Int == 8192)
            #expect(json?["max_completion_tokens"] == nil)
            return (200, Data(#"{"choices": [{"message": {"content": "ok"}}]}"#.utf8))
        }
        let output = try await makeClient().run(prompt: prompt, apiKey: "xai-test", model: "grok-4")
        #expect(output.text == "ok")
    }

    @Test func mapsUnauthorizedToSettingsHint() async {
        setHandler { _, _ in (403, Data()) }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: "bad", model: "grok-4")
        }
        #expect(message == "xAI rejected the API key. Check it in Pecto's Settings.")
    }
}
