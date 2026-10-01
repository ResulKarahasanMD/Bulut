import Foundation
import Observation
import SwiftData
import UIKit

/// Runs model replies. Lives for the whole app so a reply keeps streaming when you leave the chat screen.
@MainActor
@Observable
final class ChatEngine {
    private(set) var streamingConversationIDs: Set<UUID> = []

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var backgroundTasks: [UUID: UIBackgroundTaskIdentifier] = [:]
    @ObservationIgnored private var titleRequests: Set<UUID> = []

    /// How often streamed text is written into SwiftData (keeps the UI smooth on long answers).
    private let flushInterval: TimeInterval = 0.05

    init(app: AppModel) {
        self.app = app
    }

    func isStreaming(_ conversation: Conversation) -> Bool {
        streamingConversationIDs.contains(conversation.id)
    }

    // MARK: Actions

    func send(_ text: String, images: [PreparedImage] = [], in conversation: Conversation, context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty, !isStreaming(conversation) else { return }

        let message = ChatMessage(role: .user, content: trimmed)
        context.insert(message)
        for (index, image) in images.enumerated() {
            let stored = MessageImage(index: index, data: image.data, thumbnail: image.thumbnail)
            context.insert(stored)
            message.attach(stored)
        }
        conversation.append(message)

        if conversation.title.isEmpty {
            conversation.title = trimmed.isEmpty ? "Görsel" : ConversationTitle.fromFirstMessage(trimmed)
        }
        startReply(in: conversation, context: context)
    }

    /// Replaces the text of a user message, drops everything after it and asks the model again.
    func resend(_ message: ChatMessage, as text: String, in conversation: Conversation, context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard message.role == .user, !isStreaming(conversation), !trimmed.isEmpty || message.hasImages else { return }

        for later in conversation.sortedMessages where later.createdAt > message.createdAt {
            conversation.remove(later)
            context.delete(later)
        }
        message.content = trimmed
        conversation.updatedAt = Date()
        startReply(in: conversation, context: context)
    }

    /// Removes the last assistant reply (if any) and asks the model again.
    func regenerate(in conversation: Conversation, context: ModelContext) {
        guard !isStreaming(conversation) else { return }
        if let last = conversation.sortedMessages.last, last.role == .assistant {
            conversation.remove(last)
            context.delete(last)
        }
        guard conversation.sortedMessages.last?.role == .user else { return }
        startReply(in: conversation, context: context)
    }

    func stop(_ conversation: Conversation) {
        tasks[conversation.id]?.cancel()
    }

    func stopAll() {
        tasks.values.forEach { $0.cancel() }
    }

    // MARK: Streaming

    private func startReply(in conversation: Conversation, context: ModelContext) {
        let modelName = conversation.modelName
        let details = app.modelDetails[modelName]
        // Unknown details: send the images and let the server decide.
        let history = conversation.requestMessages(includeImages: details?.supportsVision ?? true)
        let settings = conversation.requestSettings(for: details)

        let reply = ChatMessage(role: .assistant, content: "", modelName: modelName)
        context.insert(reply)
        conversation.append(reply)

        guard let client = app.client else {
            reply.errorText = OllamaError.missingAPIKey.localizedDescription
            try? context.save()
            return
        }
        guard !modelName.isEmpty else {
            reply.errorText = "Önce bir model seç."
            try? context.save()
            return
        }
        try? context.save()

        let id = conversation.id
        streamingConversationIDs.insert(id)
        beginBackgroundTask(for: id)

        tasks[id] = Task { [weak self] in
            await self?.stream(
                client: client, model: modelName, history: history,
                options: settings.options, think: settings.think, into: reply
            )
            try? context.save()
            self?.finish(id)
            if !Task.isCancelled, reply.errorText == nil, !reply.content.isEmpty {
                await self?.generateTitleIfNeeded(for: conversation, client: client, context: context)
            }
        }
    }

    private func stream(
        client: OllamaClient,
        model: String,
        history: [OllamaChatMessage],
        options: OllamaChatOptions?,
        think: ThinkSetting?,
        into reply: ChatMessage
    ) async {
        var pendingContent = ""
        var pendingThinking = ""
        var lastFlush = Date.distantPast

        func flush() {
            if !pendingContent.isEmpty {
                reply.content += pendingContent
                pendingContent = ""
            }
            if !pendingThinking.isEmpty {
                reply.thinking += pendingThinking
                pendingThinking = ""
            }
            lastFlush = Date()
        }

        do {
            for try await chunk in client.streamChat(model: model, messages: history, options: options, think: think) {
                if let piece = chunk.message?.content { pendingContent += piece }
                if let piece = chunk.message?.thinking { pendingThinking += piece }

                if chunk.done == true {
                    reply.evalCount = chunk.evalCount
                    reply.tokensPerSecond = chunk.tokensPerSecond
                }
                if chunk.done == true || Date().timeIntervalSince(lastFlush) >= flushInterval {
                    flush()
                }
            }
            flush()
        } catch {
            flush()
            if !Self.isCancellation(error) {
                reply.errorText = error.localizedDescription
            }
        }
    }

    private func finish(_ id: UUID) {
        tasks[id] = nil
        streamingConversationIDs.remove(id)
        endBackgroundTask(for: id)
    }

    // MARK: Title

    static let autoTitleKey = "autoTitle"

    /// Asks the same model for a short title after the first successful reply. Keeps the
    /// first-message title when the setting is off or the request fails.
    private func generateTitleIfNeeded(for conversation: Conversation, client: OllamaClient, context: ModelContext) async {
        let enabled = UserDefaults.standard.object(forKey: Self.autoTitleKey) as? Bool ?? true
        let messages = conversation.sortedMessages
        guard enabled, !conversation.hasGeneratedTitle, !titleRequests.contains(conversation.id),
              let question = messages.first(where: { $0.role == .user }),
              let answer = messages.first(where: { $0.role == .assistant && !$0.content.isEmpty && $0.errorText == nil })
        else { return }

        titleRequests.insert(conversation.id)
        defer { titleRequests.remove(conversation.id) }

        let model = conversation.modelName
        let questionText = question.content.isEmpty ? "(görsel gönderdi)" : String(question.content.prefix(1500))
        let prompt = """
        Aşağıdaki sohbet için en fazla 6 kelimelik kısa bir başlık yaz. Başlık sohbetin dilinde olsun. \
        Yalnızca başlığı yaz; tırnak, emoji, Markdown ve sonda nokta kullanma.

        Kullanıcı: \(questionText)

        Asistan: \(answer.content.prefix(1500))
        """
        do {
            let raw = try await client.complete(
                model: model,
                messages: [OllamaChatMessage(role: ChatRole.user.rawValue, content: prompt)],
                options: OllamaChatOptions(temperature: 0.3),
                think: app.modelDetails[model]?.lightestThink
            )
            guard let title = ConversationTitle.clean(raw) else { return }
            conversation.title = title
            conversation.hasGeneratedTitle = true
            try? context.save()
        } catch {
            // Keep the title made from the first message.
        }
    }

    // MARK: Background time

    /// Asks iOS for a little extra time so a reply can finish if you switch apps mid-answer.
    private func beginBackgroundTask(for id: UUID) {
        let identifier = UIApplication.shared.beginBackgroundTask(withName: "ollama-reply") { [weak self] in
            // The expiration handler is called on the main thread.
            MainActor.assumeIsolated {
                self?.endBackgroundTask(for: id)
            }
        }
        backgroundTasks[id] = identifier
    }

    private func endBackgroundTask(for id: UUID) {
        guard let identifier = backgroundTasks.removeValue(forKey: id) else { return }
        if identifier != .invalid {
            UIApplication.shared.endBackgroundTask(identifier)
        }
    }

    // MARK: Helpers

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return Task.isCancelled
    }
}
