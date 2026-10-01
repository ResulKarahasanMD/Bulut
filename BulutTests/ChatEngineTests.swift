import Foundation
import SwiftData
import Testing
@testable import Bulut

/// Drives `ChatEngine` against `StubServer`. Serialized because the stub is process-wide.
@MainActor
@Suite("ChatEngine", .serialized)
final class ChatEngineTests {
    let container: ModelContainer
    let context: ModelContext
    let app: AppModel
    let engine: ChatEngine

    init() throws {
        container = try ModelContainer(
            for: Conversation.self, ChatMessage.self, MessageImage.self, Persona.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        let defaults = UserDefaults(suiteName: "BulutTests-\(UUID().uuidString)")!
        app = AppModel(apiKey: "test-key", defaults: defaults, baseURL: StubServer.baseURL)
        engine = ChatEngine(app: app)
    }

    deinit {
        StubServer.reset()
    }

    private func makeConversation() -> Conversation {
        let conversation = Conversation(modelName: "test-model")
        context.insert(conversation)
        return conversation
    }

    private func reply(in conversation: Conversation) -> ChatMessage? {
        conversation.sortedMessages.last { $0.role == .assistant }
    }

    private static func chunk(_ text: String, done: Bool = false) -> String {
        #"{"message":{"role":"assistant","content":"\#(text)"},"done":\#(done)}"#
    }

    // MARK: Happy path

    @Test func streamsReplyAndNamesTheConversation() async {
        StubServer.configure(stream: .stream([Self.chunk("Mer"), Self.chunk("haba", done: true)]))
        let conversation = makeConversation()

        engine.send("selam", in: conversation, context: context)

        #expect(await waitUntil { !engine.isStreaming(conversation) && conversation.hasGeneratedTitle })
        #expect(reply(in: conversation)?.content == "Merhaba")
        #expect(reply(in: conversation)?.errorText == nil)
        #expect(conversation.title == "Başlık")
    }

    // MARK: H1: delete while streaming

    @Test func deletingWhileStreamingNeverTouchesTheDeletedReply() async throws {
        // The first chunk is flushed at once; the second arrives within the 50 ms throttle and stays
        // pending, so cancelling forces a final flush into the reply.
        StubServer.configure(stream: .stream([Self.chunk("Mer"), Self.chunk("haba")], hold: true))
        let conversation = makeConversation()
        engine.send("selam", in: conversation, context: context)
        #expect(await waitUntil { reply(in: conversation)?.content == "Mer" })
        try await Task.sleep(for: .milliseconds(100))

        await engine.delete([conversation], context: context)

        #expect(!engine.isStreaming(conversation))
        #expect(try context.fetchCount(FetchDescriptor<Conversation>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ChatMessage>()) == 0)
        #expect(StubServer.currentLog.stopped == [true])
    }

    // MARK: H2: title request must be cancellable

    @Test func deletingCancelsAPendingTitleRequest() async throws {
        StubServer.configure(
            stream: .stream([Self.chunk("Merhaba", done: true)]),
            single: .stream([], hold: true)
        )
        let conversation = makeConversation()
        engine.send("selam", in: conversation, context: context)
        #expect(await waitUntil { StubServer.currentLog.started == [true, false] })

        await engine.delete([conversation], context: context)

        #expect(StubServer.currentLog.stopped == [false])
        #expect(try context.fetchCount(FetchDescriptor<Conversation>()) == 0)
    }

    // MARK: H4: no invisible replies

    @Test func stoppingBeforeTheFirstTokenLeavesANotice() async {
        StubServer.configure(stream: .stream([], hold: true))
        let conversation = makeConversation()
        engine.send("selam", in: conversation, context: context)
        #expect(await waitUntil { StubServer.currentLog.started == [true] })

        engine.stop(conversation)

        #expect(await waitUntil { !engine.isStreaming(conversation) })
        #expect(reply(in: conversation)?.content == "")
        #expect(reply(in: conversation)?.errorText == ChatEngine.stoppedNotice)
    }

    @Test func stoppingAfterSomeTextKeepsItWithoutAnError() async {
        StubServer.configure(stream: .stream([Self.chunk("Yarım")], hold: true))
        let conversation = makeConversation()
        engine.send("selam", in: conversation, context: context)
        #expect(await waitUntil { reply(in: conversation)?.content == "Yarım" })

        engine.stop(conversation)

        #expect(await waitUntil { !engine.isStreaming(conversation) })
        #expect(reply(in: conversation)?.content == "Yarım")
        #expect(reply(in: conversation)?.errorText == nil)
    }

    @Test func emptyServerReplyIsReported() async {
        StubServer.configure(stream: .stream(["not json", #"{"done":true}"#]))
        let conversation = makeConversation()
        engine.send("selam", in: conversation, context: context)

        #expect(await waitUntil { !engine.isStreaming(conversation) })
        #expect(reply(in: conversation)?.errorText == ChatEngine.emptyReplyNotice)
    }

    // MARK: H6: background time runs out

    @Test func backgroundExpiryCancelsAndMarksTheReply() async {
        StubServer.configure(stream: .stream([Self.chunk("Yarım")], hold: true))
        let conversation = makeConversation()
        engine.send("selam", in: conversation, context: context)
        #expect(await waitUntil { reply(in: conversation)?.content == "Yarım" })

        engine.handleBackgroundExpiry(for: conversation.id)

        // Marked at once, before iOS suspends the app.
        #expect(reply(in: conversation)?.errorText == ChatEngine.backgroundNotice)
        #expect(await waitUntil { !engine.isStreaming(conversation) })
        #expect(reply(in: conversation)?.content == "Yarım")
        #expect(StubServer.currentLog.stopped == [true])
    }
}
