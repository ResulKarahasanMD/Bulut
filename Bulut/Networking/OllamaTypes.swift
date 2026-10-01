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
    /// Base64 encoded images, only for models with the `vision` capability.
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
    /// Left out of the JSON when nil, so the model uses its own default.
    var think: ThinkSetting?
}

// MARK: - Thinking

/// The `think` value of a chat request. Depending on the model it is `true`/`false`
/// or an effort level such as "low", "high" or "max"; `/api/show` lists what a model accepts.
enum ThinkSetting: Codable, Hashable, Sendable {
    case enabled(Bool)
    case level(String)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            self = .enabled(flag)
        } else {
            self = .level(try container.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .enabled(let flag): try container.encode(flag)
        case .level(let level): try container.encode(level)
        }
    }

    /// Stored form in SwiftData: "true", "false" or the level name.
    init(storedValue: String) {
        switch storedValue {
        case "true": self = .enabled(true)
        case "false": self = .enabled(false)
        default: self = .level(storedValue)
        }
    }

    var storedValue: String {
        switch self {
        case .enabled(let flag): return flag ? "true" : "false"
        case .level(let level): return level
        }
    }

    var label: String {
        switch self {
        case .enabled(true): return "Açık"
        case .enabled(false): return "Kapalı"
        case .level("low"): return "Düşük"
        case .level("medium"): return "Orta"
        case .level("high"): return "Yüksek"
        case .level("max"): return "En yüksek"
        case .level(let level): return level
        }
    }
}

// MARK: - /api/show

struct OllamaShowResponse: Decodable, Sendable {
    struct Thinking: Decodable, Sendable {
        let values: [ThinkSetting]?
        let defaultValue: ThinkSetting?

        enum CodingKeys: String, CodingKey {
            case values
            case defaultValue = "default"
        }
    }

    /// `model_info` mixes numbers, strings and arrays; only the context length is read from it.
    struct ModelInfo: Decodable, Sendable {
        let contextLength: Int?

        private struct AnyKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyKey.self)
            // Keys look like "gptoss.context_length"; the snake-case strategy may have turned them into "…contextLength".
            let key = container.allKeys.first { key in
                key.stringValue.replacingOccurrences(of: "_", with: "").lowercased().hasSuffix("contextlength")
            }
            contextLength = key.flatMap { try? container.decode(Int.self, forKey: $0) }
        }
    }

    let capabilities: [String]?
    let thinking: Thinking?
    let modelInfo: ModelInfo?
}

/// What the app needs to know about a model to show the right controls.
struct ModelDetails: Codable, Hashable, Sendable {
    var capabilities: [String]
    var thinkOptions: [ThinkSetting]
    var defaultThink: ThinkSetting?
    var contextLength: Int?

    init(capabilities: [String], thinkOptions: [ThinkSetting], defaultThink: ThinkSetting?, contextLength: Int?) {
        self.capabilities = capabilities
        self.thinkOptions = thinkOptions
        self.defaultThink = defaultThink
        self.contextLength = contextLength
    }

    init(_ response: OllamaShowResponse) {
        self.init(
            capabilities: response.capabilities ?? [],
            thinkOptions: response.thinking?.values ?? [],
            defaultThink: response.thinking?.defaultValue,
            contextLength: response.modelInfo?.contextLength
        )
    }

    var supportsVision: Bool { capabilities.contains("vision") }

    /// Only true when the model also says which `think` values it accepts.
    var hasThinkControl: Bool { capabilities.contains("thinking") && thinkOptions.count > 1 }

    /// The cheapest accepted `think` value, used for side requests such as title generation.
    var lightestThink: ThinkSetting? {
        for candidate: ThinkSetting in [.enabled(false), .level("low"), .level("medium")] where thinkOptions.contains(candidate) {
            return candidate
        }
        return nil
    }
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
