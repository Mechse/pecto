import Foundation
import Testing
@testable import PectoKit

private func makeClient() -> GeminiClient {
    GeminiClient(session: mockedSession())
}

private func setHandler(_ handler: MockURLProtocol.Handler?) {
    MockURLProtocol.setHandler(forHost: "generativelanguage.googleapis.com", handler)
}

private let prompt = RunPrompt(system: "You are executing the task.", user: "Improve this: my draft")

@Suite(.serialized) struct GeminiClientTests {
    @Test func sendsWellFormedRequestAndDecodesResult() async throws {
        setHandler { request, body in
            #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test")

            let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let system = json?["system_instruction"] as? [String: Any]
            let systemParts = system?["parts"] as? [[String: Any]]
            #expect(systemParts?[0]["text"] as? String == "You are executing the task.")
            let contents = json?["contents"] as? [[String: Any]]
            #expect(contents?.count == 1)
            #expect(contents?[0]["role"] as? String == "user")
            let userParts = contents?[0]["parts"] as? [[String: Any]]
            #expect(userParts?[0]["text"] as? String == "Improve this: my draft")
            let config = json?["generationConfig"] as? [String: Any]
            #expect(config?["maxOutputTokens"] as? Int == 8192)

            let response = """
            {"candidates": [{"content": {"parts": [{"text": "Part one. "}, {"text": "Part two."}], "role": "model"}}], "usageMetadata": {"promptTokenCount": 21, "candidatesTokenCount": 9}}
            """
            return (200, Data(response.utf8))
        }
        let output = try await makeClient().run(prompt: prompt, apiKey: "AIza-test", model: "gemini-2.5-flash")
        #expect(output.text == "Part one. Part two.")
        #expect(output.usage == RunUsage(inputTokens: 21, outputTokens: 9))
    }

    @Test func safetyBlockBecomesReadableError() async {
        setHandler { _, _ in
            (200, Data(#"{"promptFeedback": {"blockReason": "SAFETY"}}"#.utf8))
        }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: "AIza-test", model: "gemini-2.5-flash")
        }
        #expect(message == "Gemini declined this prompt (SAFETY). Your clipboard is unchanged.")
    }

    @Test func emptyResponseWithoutFeedbackBecomesReadableError() async {
        setHandler { _, _ in (200, Data("{}".utf8)) }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: "AIza-test", model: "gemini-2.5-flash")
        }
        #expect(message == "Gemini returned no result for this prompt.")
    }

    @Test func invalidKeyOn400IsMappedToSettingsHint() async {
        setHandler { _, _ in
            let body = #"{"error": {"code": 400, "message": "API key not valid.", "status": "INVALID_ARGUMENT", "details": [{"reason": "API_KEY_INVALID"}]}}"#
            return (400, Data(body.utf8))
        }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: "bad", model: "gemini-2.5-flash")
        }
        #expect(message == "Google Gemini rejected the API key. Check it in Pecto's Settings.")
    }

    @Test func surfacesAPIErrorMessages() async {
        setHandler { _, _ in
            (429, Data(#"{"error": {"code": 429, "message": "Quota exceeded.", "status": "RESOURCE_EXHAUSTED"}}"#.utf8))
        }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: "AIza-test", model: "gemini-2.5-flash")
        }
        #expect(message == "Quota exceeded.")
    }

    @Test func mapsNetworkFailuresToFriendlyMessage() async {
        setHandler { _, _ in throw URLError(.notConnectedToInternet) }
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: "AIza-test", model: "gemini-2.5-flash")
        }
        #expect(message == "Couldn't reach the Google Gemini API. Check your internet connection and try again.")
    }

    @Test func rejectsMissingKeyBeforeAnyRequest() async {
        let message = await runErrorMessage {
            try await makeClient().run(prompt: prompt, apiKey: nil, model: "gemini-2.5-flash")
        }
        #expect(message == "Add your Google Gemini API key in Pecto's Settings first.")
    }

    @Test func validateKeyHitsModelsEndpoint() async throws {
        setHandler { request, _ in
            #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models")
            #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "AIza-test")
            return (200, Data(#"{"models": []}"#.utf8))
        }
        try await makeClient().validateKey("AIza-test")
    }
}
