#if DEBUG
import SwiftData
import SwiftUI

/// Self-contained data for `#Preview`s: an in-memory store, no API key, so nothing reaches the network.
@MainActor
enum PreviewData {
    static let markdownReply = """
    ## Demleme yöntemleri
    Üç yaygın yöntem var:
    1. **French press**: 4 dakika demleme
    2. *V60*: orta-ince öğütüm
    - [x] Su 93 °C
    > Kahve demlemeden hemen önce öğütülmeli.

    | Yöntem | Süre |
    |---|---|
    | French press | 4 dk |
    | V60 | 3 dk |

    ```swift
    let water = 250 // ml
    let coffee = water / 16
    ```
    """

    static func container() -> ModelContainer {
        let container = try! ModelContainer(
            for: Conversation.self, ChatMessage.self, MessageImage.self, Persona.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let conversation = Conversation(modelName: "gpt-oss:120b")
        conversation.title = "Kahve demleme"
        context.insert(conversation)
        for message in [
            message(.user, "Kahve nasıl demlenir?"),
            message(.assistant, markdownReply, thinking: "Kullanıcı demleme yöntemlerini soruyor."),
        ] {
            context.insert(message)
            conversation.append(message)
        }
        return container
    }

    static func conversation(in container: ModelContainer) -> Conversation {
        try! container.mainContext.fetch(FetchDescriptor<Conversation>()).first!
    }

    static func message(_ role: ChatRole, _ content: String, thinking: String = "", error: String? = nil) -> ChatMessage {
        let message = ChatMessage(role: role, content: content, modelName: role == .assistant ? "gpt-oss:120b" : nil)
        message.thinking = thinking
        message.errorText = error
        return message
    }

    /// No key: `client` is nil, so model and title requests return before touching the network.
    static func app() -> AppModel {
        AppModel(apiKey: nil, defaults: UserDefaults(suiteName: "BulutPreviews")!)
    }
}
#endif
