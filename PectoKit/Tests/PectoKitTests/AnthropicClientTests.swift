import Foundation
import Testing
@testable import PectoKit

/// Serialized because the mock's handler is process-global state.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest, Data) throws -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (status, data) = try handler(request, Self.bodyData(of: request))
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    /// URLSession hands POST bodies to protocols as a stream, not `httpBody`.
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private func makeClient() -> AnthropicClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return AnthropicClient(session: URLSession(configuration: configuration))
}

private let prompt = RunPrompt(system: "You are executing the task.", user: "Improve this: my draft")

private func runErrorMessage(_ body: () async throws -> String) async -> String? {
    do {
        _ = try await body()
        return nil
    } catch let error as RunError {
        return error.message
    } catch {
        return "unexpected error type"
    }
}

@Suite(.serialized) struct AnthropicClientTests {
    @Test func sendsWellFormedRequestAndConcatenatesTextBlocks() async throws {
        MockURLProtocol.handler = { request, body in
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
            {"content": [{"type": "text", "text": "Part one. "}, {"type": "tool_use", "id": "x"}, {"type": "text", "text": "Part two."}], "stop_reason": "end_turn"}
            """
            return (200, Data(response.utf8))
        }
        let text = try await makeClient().run(prompt: prompt, apiKey: "sk-test")
        #expect(text == "Part one. Part two.")
    }

    @Test func surfacesAPIErrorMessages() async {
        MockURLProtocol.handler = { _, _ in
            (429, Data(#"{"error": {"type": "rate_limit_error", "message": "Rate limited, slow down."}}"#.utf8))
        }
        let message = await runErrorMessage { try await makeClient().run(prompt: prompt, apiKey: "sk-test") }
        #expect(message == "Rate limited, slow down.")
    }

    @Test func mapsUnauthorizedToSettingsHint() async {
        MockURLProtocol.handler = { _, _ in
            (401, Data(#"{"error": {"type": "authentication_error", "message": "invalid x-api-key"}}"#.utf8))
        }
        let message = await runErrorMessage { try await makeClient().run(prompt: prompt, apiKey: "bad") }
        #expect(message == "Anthropic rejected the API key. Check it in Pecto's Settings.")
    }

    @Test func fallsBackOnUnreadableErrorBody() async {
        MockURLProtocol.handler = { _, _ in (500, Data("<html>oops</html>".utf8)) }
        let message = await runErrorMessage { try await makeClient().run(prompt: prompt, apiKey: "sk-test") }
        #expect(message == "The Anthropic API returned an error (HTTP 500).")
    }

    @Test func mapsNetworkFailuresToFriendlyMessage() async {
        MockURLProtocol.handler = { _, _ in throw URLError(.notConnectedToInternet) }
        let message = await runErrorMessage { try await makeClient().run(prompt: prompt, apiKey: "sk-test") }
        #expect(message == "Couldn't reach the Anthropic API. Check your internet connection and try again.")
    }
}
