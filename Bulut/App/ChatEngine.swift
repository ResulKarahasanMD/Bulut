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

    /// How often streamed text is written into SwiftData (keeps the UI smooth on long answers).
    private let flushInterval: TimeInterval = 0.05

    init(app: AppModel) {
        self.app = app
    }

    func isStreaming(_ conversation: Conversation) -> Bool {
        streamingConversationIDs.contains(conversation.id)
    }

    // MARK: Actions

    func send(_ text: String, in conversation: Conversation, context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming(conversation) else { return }

        let message = ChatMessage(role: .user, content: trimmed)
        context.insert(message)
        conversation.append(message)

        if conversation.title.isEmpty {
            conversation.title = Self.makeTitle(from: trimmed)
        }
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
        let history = conversation.requestMessages()

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
            await self?.stream(client: client, model: modelName, history: history, into: reply)
            try? context.save()
            self?.finish(id)
        }
    }

    private func stream(client: OllamaClient, model: String, history: [OllamaChatMessage], into reply: ChatMessage) async {
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
            for try await chunk in client.streamChat(model: model, messages: history) {
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

    private static func makeTitle(from text: String) -> String {
        let singleLine = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard singleLine.count > 48 else { return singleLine }
        return String(singleLine.prefix(48)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
