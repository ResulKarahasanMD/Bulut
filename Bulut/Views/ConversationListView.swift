import SwiftData
import SwiftUI

struct ConversationListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(ChatEngine.self) private var engine

    @Query(sort: \Conversation.updatedAt, order: .reverse) private var conversations: [Conversation]
    @Query(sort: \Persona.createdAt) private var personas: [Persona]
    @AppStorage("defaultSystemPrompt") private var defaultSystemPrompt = ""

    @State private var path: [Conversation] = []
    @State private var searchText = ""
    @State private var isShowingSettings = false

    private var filtered: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return conversations }
        return conversations.filter { conversation in
            conversation.title.localizedStandardContains(query)
                || (conversation.messages ?? []).contains { $0.content.localizedStandardContains(query) }
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(filtered) { conversation in
                    NavigationLink(value: conversation) {
                        ConversationRow(
                            conversation: conversation,
                            isStreaming: engine.isStreaming(conversation)
                        )
                    }
                }
                .onDelete(perform: delete)
            }
            .listStyle(.plain)
            .overlay {
                if conversations.isEmpty {
                    ContentUnavailableView {
                        Label("Henüz sohbet yok", systemImage: "cloud")
                    } description: {
                        Text("Yeni bir sohbet başlatmak için sağ üstteki kaleme dokun.")
                    } actions: {
                        Button("Yeni sohbet", action: newConversation)
                            .buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .searchable(text: $searchText, prompt: "Sohbetlerde ara")
            .navigationTitle("Sohbetler")
            .navigationDestination(for: Conversation.self) { conversation in
                ChatView(conversation: conversation)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Ayarlar")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Tap: new chat. Long press: new chat with a persona.
                    Menu {
                        ForEach(personas) { persona in
                            Button(persona.name) { newConversation(persona: persona) }
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    } primaryAction: {
                        newConversation()
                    }
                    .accessibilityLabel("Yeni sohbet")
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .task {
                await app.refreshModels()
            }
            .onChange(of: path) {
                if path.isEmpty { removeEmptyConversations() }
            }
        }
    }

    // MARK: Actions

    private func newConversation() {
        newConversation(persona: nil)
    }

    private func newConversation(persona: Persona?) {
        let conversation = Conversation(
            modelName: app.defaultModel.isEmpty ? (app.modelNames.first ?? "") : app.defaultModel,
            systemPrompt: persona?.systemPrompt ?? defaultSystemPrompt
        )
        context.insert(conversation)
        path = [conversation]
    }

    private func delete(at offsets: IndexSet) {
        let items = offsets.map { filtered[$0] }
        for conversation in items {
            engine.stop(conversation)
            context.delete(conversation)
        }
        try? context.save()
    }

    /// Drops chats that were opened but never used, once you are back on the list.
    private func removeEmptyConversations() {
        for conversation in conversations where (conversation.messages ?? []).isEmpty {
            context.delete(conversation)
        }
        try? context.save()
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(conversation.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if isStreaming {
                    ProgressView().controlSize(.small)
                } else {
                    Text(conversation.updatedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(conversation.lastMessagePreview)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(conversation.modelName)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
