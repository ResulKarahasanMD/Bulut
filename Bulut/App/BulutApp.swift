import SwiftData
import SwiftUI

@main
struct BulutApp: App {
    @State private var app: AppModel
    @State private var engine: ChatEngine

    init() {
        let app = AppModel()
        _app = State(initialValue: app)
        _engine = State(initialValue: ChatEngine(app: app))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(engine)
        }
        .modelContainer(for: [Conversation.self, ChatMessage.self])
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            if app.hasAPIKey {
                ConversationListView()
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: app.hasAPIKey)
    }
}
