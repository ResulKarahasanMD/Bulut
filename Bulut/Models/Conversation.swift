import Foundation
import SwiftData

enum ChatRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

@Model
final class Conversation {
    var id: UUID = UUID()
    var title: String = ""
    var modelName: String = ""
    var systemPrompt: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// Request settings for this conversation; nil means the model's own default.
    var temperature: Double?
    var contextLength: Int?
    /// `ThinkSetting.storedValue`; see `think`.
    var thinkValue: String?
    /// Set once the model has named the conversation, so the title is generated only once.
    var hasGeneratedTitle: Bool = false

    // Optional + defaults keep the schema compatible with CloudKit sync later on.
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage]? = []

    init(modelName: String, systemPrompt: String = "") {
        self.id = UUID()
        self.title = ""
        self.modelName = modelName
        self.systemPrompt = systemPrompt
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Attaches a message through the to-many side so `messages` is up to date immediately.
    func append(_ message: ChatMessage) {
        if messages == nil { messages = [] }
        messages?.append(message)
        updatedAt = Date()
    }

    /// Detaches a message; the caller still deletes it from the context.
    func remove(_ message: ChatMessage) {
        messages?.removeAll { $0.id == message.id }
    }

    var displayTitle: String {
        title.isEmpty ? "Yeni sohbet" : title
    }

    var sortedMessages: [ChatMessage] {
        (messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    var lastMessagePreview: String {
        guard let last = sortedMessages.last else { return "Henüz mesaj yok" }
        if last.content.isEmpty, let error = last.errorText { return error }
        if last.content.isEmpty, last.hasImages { return "Görsel" }
        return last.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    var think: ThinkSetting? {
        get { thinkValue.map(ThinkSetting.init(storedValue:)) }
        set { thinkValue = newValue?.storedValue }
    }

    /// Options and `think` for a request to a model with the given details. Values the model does
    /// not accept (e.g. after switching models) are dropped instead of being sent.
    func requestSettings(for details: ModelDetails?) -> (options: OllamaChatOptions?, think: ThinkSetting?) {
        var numCtx = contextLength
        if let requested = numCtx, let limit = details?.contextLength {
            numCtx = min(requested, limit)
        }
        let options = (temperature == nil && numCtx == nil) ? nil : OllamaChatOptions(temperature: temperature, numCtx: numCtx)
        let accepted = think.flatMap { value in details?.thinkOptions.contains(value) == true ? value : nil }
        return (options, accepted)
    }

    /// The history sent to the model: optional system prompt + every non-error message with content.
    /// Images are only included for vision models; image-only messages are skipped otherwise.
    func requestMessages(includeImages: Bool = true) -> [OllamaChatMessage] {
        var result: [OllamaChatMessage] = []
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            result.append(OllamaChatMessage(role: ChatRole.system.rawValue, content: system))
        }
        for message in sortedMessages where message.errorText == nil {
            let images = includeImages ? message.sortedImages.map { $0.data.base64EncodedString() } : []
            guard !message.content.isEmpty || !images.isEmpty else { continue }
            result.append(OllamaChatMessage(role: message.roleRaw, content: message.content, images: images.isEmpty ? nil : images))
        }
        return result
    }

    /// Markdown transcript used for sharing.
    func transcript() -> String {
        var lines = ["# \(displayTitle)", ""]
        for message in sortedMessages where !message.content.isEmpty || message.hasImages {
            let speaker = message.role == .user ? "Sen" : (message.modelName ?? modelName)
            lines.append("**\(speaker):**")
            if message.hasImages {
                lines.append("_[\(message.images?.count ?? 0) görsel]_")
            }
            if !message.content.isEmpty {
                lines.append(message.content)
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

@Model
final class ChatMessage {
    var id: UUID = UUID()
    var roleRaw: String = ChatRole.user.rawValue
    var content: String = ""
    var thinking: String = ""
    var createdAt: Date = Date()
    var modelName: String?
    var evalCount: Int?
    var tokensPerSecond: Double?
    var errorText: String?
    var conversation: Conversation?

    @Relationship(deleteRule: .cascade, inverse: \MessageImage.message)
    var images: [MessageImage]? = []

    init(role: ChatRole, content: String, modelName: String? = nil) {
        self.id = UUID()
        self.roleRaw = role.rawValue
        self.content = content
        self.thinking = ""
        self.createdAt = Date()
        self.modelName = modelName
    }

    var role: ChatRole {
        ChatRole(rawValue: roleRaw) ?? .user
    }

    var sortedImages: [MessageImage] {
        (images ?? []).sorted { $0.index < $1.index }
    }

    var hasImages: Bool {
        !(images ?? []).isEmpty
    }

    func attach(_ image: MessageImage) {
        if images == nil { images = [] }
        images?.append(image)
    }
}

/// A photo sent with a user message. Both JPEGs live outside the SQLite file.
@Model
final class MessageImage {
    var id: UUID = UUID()
    var index: Int = 0
    /// Downscaled JPEG sent to the model.
    @Attribute(.externalStorage) var data: Data = Data()
    /// Small JPEG shown in the chat bubble.
    @Attribute(.externalStorage) var thumbnail: Data = Data()
    var message: ChatMessage?

    init(index: Int, data: Data, thumbnail: Data) {
        self.id = UUID()
        self.index = index
        self.data = data
        self.thumbnail = thumbnail
    }
}
