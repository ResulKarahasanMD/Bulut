import Foundation
@testable import Bulut

/// Fake Ollama server for `https://bulut.test`. Registered on `URLSession.shared`, which is the
/// session `OllamaClient` uses, so no production code needs a seam for the transport.
final class StubServer: URLProtocol, @unchecked Sendable {
    static let baseURL = URL(string: "https://bulut.test")!

    /// What one request gets back. `hold` keeps the connection open until the client cancels it.
    struct Reply: Sendable {
        var lines: [String]
        var hold: Bool

        static func stream(_ lines: [String], hold: Bool = false) -> Reply {
            Reply(lines: lines, hold: hold)
        }
    }

    struct Log: Sendable {
        var started: [Bool] = []   // isStreaming flag of each started request
        var stopped: [Bool] = []   // isStreaming flag of each request the client cancelled
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var streamReply = Reply.stream([])
    nonisolated(unsafe) private static var singleReply = Reply.stream([])
    nonisolated(unsafe) private static var log = Log()

    /// Installs the replies for `stream: true` and `stream: false` chat requests and clears the log.
    static func configure(stream: Reply, single: Reply = .stream([#"{"message":{"content":"Başlık"},"done":true}"#])) {
        lock.withLock {
            streamReply = stream
            singleReply = single
            log = Log()
        }
        URLProtocol.registerClass(StubServer.self)
    }

    static func reset() {
        URLProtocol.unregisterClass(StubServer.self)
        lock.withLock { log = Log() }
    }

    static var currentLog: Log { lock.withLock { log } }

    private var isStreamingRequest = false
    private var finished = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == baseURL.host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        isStreamingRequest = Self.streamFlag(of: request)
        let reply = Self.lock.withLock {
            Self.log.started.append(isStreamingRequest)
            return isStreamingRequest ? Self.streamReply : Self.singleReply
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/x-ndjson"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.lines.isEmpty {
            let body = reply.lines.joined(separator: "\n") + "\n"
            client?.urlProtocol(self, didLoad: Data(body.utf8))
        }
        if !reply.hold {
            finished = true
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        guard !finished else { return }
        Self.lock.withLock { Self.log.stopped.append(isStreamingRequest) }
    }

    private static func streamFlag(of request: URLRequest) -> Bool {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            body = data
        }
        guard let body,
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return false }
        return object["stream"] as? Bool ?? false
    }
}

/// Polls on the main actor until `condition` holds; records an issue and returns false on timeout.
@MainActor
@discardableResult
func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !condition() {
        if clock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
