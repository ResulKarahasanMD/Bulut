import Foundation

/// Minimal client for Ollama Cloud (https://ollama.com/api). Talks to the cloud directly, no local Ollama needed.
struct OllamaClient: Sendable {
    static let baseURL = URL(string: "https://ollama.com")!

    let apiKey: String
    var baseURL: URL = OllamaClient.baseURL

    init(apiKey: String, baseURL: URL = OllamaClient.baseURL) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    private var session: URLSession { .shared }

    // MARK: Models

    /// Lists the models available on Ollama Cloud (`GET /api/tags`).
    func listModels() async throws -> [OllamaModel] {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        try Self.validate(response, body: data)
        let decoded = try OllamaCoding.makeDecoder().decode(OllamaTagsResponse.self, from: data)
        return decoded.models.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    // MARK: Key check

    /// `/api/tags` is public, so the only reliable way to check a key is an authenticated call.
    /// This sends a one-token, non-streaming chat request.
    func verifyKey(using model: String) async throws {
        let body = OllamaChatRequest(
            model: model,
            messages: [OllamaChatMessage(role: "user", content: "ping")],
            stream: false,
            options: OllamaChatOptions(numPredict: 1)
        )
        var request = try makeChatRequest(body)
        request.timeoutInterval = 60
        let (data, response) = try await session.data(for: request)
        try Self.validate(response, body: data)
    }

    // MARK: Chat (streaming)

    /// Streams `/api/chat` as NDJSON chunks. Cancelling the consuming task cancels the HTTP request.
    func streamChat(
        model: String,
        messages: [OllamaChatMessage],
        options: OllamaChatOptions? = nil
    ) -> AsyncThrowingStream<OllamaChatChunk, Error> {
        let body = OllamaChatRequest(model: model, messages: messages, stream: true, options: options)
        let session = self.session

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeChatRequest(body)
                    let (bytes, response) = try await session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw OllamaError.invalidResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var errorBody = Data()
                        for try await byte in bytes {
                            errorBody.append(byte)
                            if errorBody.count > 16_384 { break }
                        }
                        throw OllamaError.from(status: http.statusCode, body: errorBody)
                    }

                    let decoder = OllamaCoding.makeDecoder()
                    for try await line in bytes.lines {
                        guard let chunk = try Self.decodeLine(line, decoder: decoder) else { continue }
                        continuation.yield(chunk)
                        if chunk.done == true { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Helpers

    /// Decodes one NDJSON line. Returns nil for blank or unparseable lines; throws when the line is an `{"error": ...}` object.
    static func decodeLine(_ line: String, decoder: JSONDecoder = OllamaCoding.makeDecoder()) throws -> OllamaChatChunk? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let chunk = try? decoder.decode(OllamaChatChunk.self, from: Data(trimmed.utf8)) else {
            return nil
        }
        if let message = chunk.error {
            throw OllamaError.server(message)
        }
        return chunk
    }

    private func makeChatRequest(_ body: OllamaChatRequest) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson, application/json", forHTTPHeaderField: "Accept")
        // Thinking models can take a while before the first token arrives.
        request.timeoutInterval = 300
        request.httpBody = try OllamaCoding.makeEncoder().encode(body)
        return request
    }

    private static func validate(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw OllamaError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw OllamaError.from(status: http.statusCode, body: body)
        }
    }
}
