import Foundation

// MARK: - /api/tags

struct OllamaModel: Codable, Hashable, Identifiable, Sendable {
    let name: String
    let model: String?
    let modifiedAt: String?
    let size: Int64?

    var id: String { name }
}

struct OllamaTagsResponse: Codable, Sendable {
    let models: [OllamaModel]
}

// MARK: - /api/chat request

struct OllamaChatMessage: Codable, Hashable, Sendable {
    var role: String
    var content: String
    /// Base64 encoded images (vision models). Not used in the MVP UI yet.
    var images: [String]?

    init(role: String, content: String, images: [String]? = nil) {
        self.role = role
        self.content = content
        self.images = images
    }
}

struct OllamaChatOptions: Codable, Hashable, Sendable {
    var temperature: Double?
    var numPredict: Int?
    var numCtx: Int?

    init(temperature: Double? = nil, numPredict: Int? = nil, numCtx: Int? = nil) {
        self.temperature = temperature
        self.numPredict = numPredict
        self.numCtx = numCtx
    }
}

struct OllamaChatRequest: Encodable, Sendable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    var options: OllamaChatOptions?
}

// MARK: - /api/chat response (one NDJSON line per chunk when streaming)

struct OllamaChatChunk: Decodable, Sendable {
    struct Message: Decodable, Sendable {
        let role: String?
        let content: String?
        let thinking: String?
    }

    let model: String?
    let message: Message?
    let done: Bool?
    let doneReason: String?
    let totalDuration: Int64?
    let promptEvalCount: Int?
    let evalCount: Int?
    let evalDuration: Int64?
    /// Ollama reports some failures as `{"error": "..."}`, even mid-stream.
    let error: String?

    /// Generation speed reported by the server, in tokens per second.
    var tokensPerSecond: Double? {
        guard let evalCount, let evalDuration, evalDuration > 0 else { return nil }
        return Double(evalCount) / (Double(evalDuration) / 1_000_000_000)
    }
}

struct OllamaErrorBody: Decodable, Sendable {
    let error: String
}

// MARK: - Coders

enum OllamaCoding {
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
