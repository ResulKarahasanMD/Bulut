import Foundation

enum OllamaError: LocalizedError, Equatable, Sendable {
    case missingAPIKey
    case unauthorized
    case forbidden(String?)
    case notFound(String?)
    case rateLimited(String?)
    case http(status: Int, message: String?)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "API anahtarı yok. Ayarlar'dan bir anahtar ekle."
        case .unauthorized:
            return "API anahtarı geçersiz ya da iptal edilmiş (401)."
        case .forbidden(let message):
            return "Bu işlem için yetki yok (403)." + Self.suffix(message)
        case .notFound(let message):
            return "Model bulunamadı (404)." + Self.suffix(message)
        case .rateLimited(let message):
            return "Kullanım limitine ulaşıldı (429). Biraz sonra tekrar dene." + Self.suffix(message)
        case .http(let status, let message):
            return "Sunucu hatası (\(status))." + Self.suffix(message)
        case .server(let message):
            return message
        case .invalidResponse:
            return "Sunucudan beklenmeyen bir yanıt geldi."
        }
    }

    private static func suffix(_ message: String?) -> String {
        guard let message, !message.isEmpty else { return "" }
        return " " + message
    }

    /// Maps a non-2xx HTTP response to a typed error, using Ollama's `{"error": "..."}` body when present.
    static func from(status: Int, body: Data) -> OllamaError {
        let message: String? = {
            if let decoded = try? JSONDecoder().decode(OllamaErrorBody.self, from: body) {
                return decoded.error
            }
            let text = String(decoding: body.prefix(500), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }()

        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden(message)
        case 404: return .notFound(message)
        case 429: return .rateLimited(message)
        default: return .http(status: status, message: message)
        }
    }
}
