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
        return last.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The history sent to the model: optional system prompt + every non-error message with content.
    func requestMessages() -> [OllamaChatMessage] {
        var result: [OllamaChatMessage] = []
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            result.append(OllamaChatMessage(role: ChatRole.system.rawValue, content: system))
        }
        for message in sortedMessages where message.errorText == nil && !message.content.isEmpty {
            result.append(OllamaChatMessage(role: message.roleRaw, content: message.content))
        }
        return result
    }

    /// Markdown transcript used for sharing.
    func transcript() -> String {
        var lines = ["# \(displayTitle)", ""]
        for message in sortedMessages where !message.content.isEmpty {
            let speaker = message.role == .user ? "Sen" : (message.modelName ?? modelName)
            lines.append("**\(speaker):**")
            lines.append(message.content)
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
}
