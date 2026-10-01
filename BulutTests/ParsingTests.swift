import Foundation
import Testing
@testable import Bulut

@Suite("Markdown parser")
struct MarkdownParserTests {
    @Test func headingsListsAndRules() {
        let blocks = MarkdownParser.parse("# Başlık\n- bir\n  - iki\n1. üç\n---")
        #expect(blocks == [
            .heading(level: 1, text: "Başlık"),
            .listItem(indent: 0, marker: "•", text: "bir"),
            .listItem(indent: 1, marker: "•", text: "iki"),
            .listItem(indent: 0, marker: "1.", text: "üç"),
            .rule,
        ])
    }

    @Test func unclosedFenceRunsToTheEnd() {
        // While a reply streams, the closing fence has not arrived yet.
        let blocks = MarkdownParser.parse("Kod:\n```swift\nlet a = 1\nlet b = 2")
        #expect(blocks == [
            .paragraph("Kod:"),
            .code(language: "swift", code: "let a = 1\nlet b = 2"),
        ])
    }

    @Test func tableRowsArePaddedToHeaderWidth() {
        let blocks = MarkdownParser.parse("| a | b |\n|---|:-:|\n| 1 |\n| 2 | 3 | 4 |")
        #expect(blocks == [.table(header: ["a", "b"], rows: [["1", ""], ["2", "3"]])])
    }

    @Test func pipeLinesWithoutSeparatorStayParagraphs() {
        #expect(MarkdownParser.parse("| not a table") == [.paragraph("| not a table")])
    }

    @Test func quotesAndHashtags() {
        let blocks = MarkdownParser.parse("> alıntı\n> devam\n#etiket")
        #expect(blocks == [.quote("alıntı\ndevam"), .paragraph("#etiket")])
    }
}

@Suite("NDJSON and errors")
struct NetworkingDecodingTests {
    @Test func decodesContentAndThinkingChunks() throws {
        let chunk = try #require(try OllamaClient.decodeLine(#"{"message":{"role":"assistant","content":"Mer","thinking":"hm"},"done":false}"#))
        #expect(chunk.message?.content == "Mer")
        #expect(chunk.message?.thinking == "hm")
        #expect(chunk.done == false)
    }

    @Test func blankAndBrokenLinesAreSkipped() throws {
        #expect(try OllamaClient.decodeLine("   ") == nil)
        #expect(try OllamaClient.decodeLine("{not json") == nil)
    }

    @Test func midStreamErrorThrows() {
        #expect(throws: OllamaError.server("model overloaded")) {
            try OllamaClient.decodeLine(#"{"error":"model overloaded"}"#)
        }
    }

    @Test func doneChunkReportsSpeed() throws {
        let chunk = try #require(try OllamaClient.decodeLine(#"{"done":true,"eval_count":50,"eval_duration":2000000000}"#))
        #expect(chunk.tokensPerSecond == 25)
    }

    @Test func httpStatusMapping() {
        let body = Data(#"{"error":"Unauthorized"}"#.utf8)
        #expect(OllamaError.from(status: 401, body: body) == .unauthorized)
        #expect(OllamaError.from(status: 404, body: Data(#"{"error":"no such model"}"#.utf8)) == .notFound("no such model"))
        #expect(OllamaError.from(status: 429, body: Data()) == .rateLimited(nil))
        #expect(OllamaError.from(status: 502, body: Data("Bad Gateway".utf8)) == .http(status: 502, message: "Bad Gateway"))
    }

    @Test func showResponseReadsCapabilitiesThinkAndContext() throws {
        let json = #"""
        {"capabilities":["completion","thinking","vision"],
         "thinking":{"values":["low","medium","high"],"default":"medium"},
         "model_info":{"gptoss.context_length":131072,"general.architecture":"gptoss"}}
        """#
        let details = try OllamaClient.decodeShow(Data(json.utf8))
        #expect(details.supportsVision)
        #expect(details.hasThinkControl)
        #expect(details.thinkOptions == [.level("low"), .level("medium"), .level("high")])
        #expect(details.defaultThink == .level("medium"))
        #expect(details.contextLength == 131072)
        #expect(details.lightestThink == .level("low"))
    }
}

@Suite("Think setting and titles")
struct ThinkAndTitleTests {
    @Test(arguments: [ThinkSetting.enabled(true), .enabled(false), .level("high")])
    func storedValueRoundTrips(_ value: ThinkSetting) {
        #expect(ThinkSetting(storedValue: value.storedValue) == value)
    }

    @Test func encodesAsBoolOrString() throws {
        let encoder = JSONEncoder()
        #expect(String(decoding: try encoder.encode(ThinkSetting.enabled(false)), as: UTF8.self) == "false")
        #expect(String(decoding: try encoder.encode(ThinkSetting.level("low")), as: UTF8.self) == #""low""#)
    }

    @Test func requestLeavesThinkOutWhenNil() throws {
        let request = OllamaChatRequest(model: "m", messages: [], stream: true, options: nil, think: nil)
        let json = String(decoding: try OllamaCoding.makeEncoder().encode(request), as: UTF8.self)
        #expect(!json.contains("think"))
    }

    @Test func cleansModelWrittenTitles() {
        #expect(ConversationTitle.clean("**Başlık:** Kahve demleme yöntemleri.") == "Kahve demleme yöntemleri")
        #expect(ConversationTitle.clean("\n\n\"Swift eşzamanlılık\"\nek satır") == "Swift eşzamanlılık")
        #expect(ConversationTitle.clean("  **  ") == nil)
    }

    @Test func firstMessageTitleIsShortenedToOneLine() {
        let long = String(repeating: "a", count: 60)
        #expect(ConversationTitle.fromFirstMessage("bir\niki") == "bir iki")
        #expect(ConversationTitle.fromFirstMessage(long) == String(repeating: "a", count: 48) + "…")
    }
}
