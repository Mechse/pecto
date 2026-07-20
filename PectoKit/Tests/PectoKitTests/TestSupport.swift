import Foundation
@testable import PectoKit

/// Mock transport shared by all client suites. Handlers are keyed by host so
/// suites for different providers can run in parallel; within one suite the
/// tests stay `.serialized` because they swap their host's handler.
final class MockURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest, Data) throws -> (Int, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    static func setHandler(forHost host: String, _ handler: Handler?) {
        lock.lock()
        defer { lock.unlock() }
        handlers[host] = handler
    }

    private static func handler(forHost host: String?) -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        guard let host else { return nil }
        return handlers[host]
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let handler = Self.handler(forHost: request.url?.host) else {
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

func mockedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: configuration)
}

func runErrorMessage<T>(_ body: () async throws -> T) async -> String? {
    do {
        _ = try await body()
        return nil
    } catch let error as RunError {
        return error.message
    } catch {
        return "unexpected error type"
    }
}
