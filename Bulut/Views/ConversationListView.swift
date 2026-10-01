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
    /// Non-nil while the delete confirmation is shown.
    @State private var conversationToDelete: Conversation?

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
                    // Not `.onDelete`: List removes that row at once and raises an inconsistency
                    // exception when the data is still there (it is, until you confirm).
                    // No destructive role either, so the row is never hidden ahead of the data.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            confirmDelete(conversation)
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
            .listStyle(.plain)
            .confirmationDialog("Sohbet silinsin mi?", item: $conversationToDelete, titleVisibility: .visible) { conversation in
                Button("Sil", role: .destructive) { delete(conversation) }
            } message: { conversation in
                Text(deleteMessage(for: conversation))
            }
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
                // Never moves into the overflow menu, however narrow the bar gets.
                ToolbarItem(placement: .topBarPinnedTrailing) { newConversationMenu }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .task {
                // Chats left empty when the app was closed inside them.
                removeEmptyConversations()
                await app.refreshModels()
            }
            .onChange(of: path) {
                if path.isEmpty { removeEmptyConversations() }
            }
        }
    }

    /// Tap: new chat. Long press: new chat with a persona.
    private var newConversationMenu: some View {
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

    /// Swipe to delete asks first; a whole conversation cannot be brought back.
    private func confirmDelete(_ conversation: Conversation) {
        conversationToDelete = conversation
    }

    private func deleteMessage(for conversation: Conversation) -> String {
        let base = "“\(conversation.displayTitle)” ve tüm mesajları silinecek."
        return engine.isStreaming(conversation) ? base + " Süren yanıt durdurulacak." : base
    }

    private func delete(_ conversation: Conversation) {
        Task { await engine.delete([conversation], context: context) }
    }

    /// Drops chats that were opened but never used: on launch and whenever you are back on the
    /// list. The chat that is open right now is kept.
    private func removeEmptyConversations() {
        for conversation in conversations where (conversation.messages ?? []).isEmpty && !path.contains(conversation) {
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

#if DEBUG
#Preview("Sohbetler") {
    let app = PreviewData.app()
    ConversationListView()
        .environment(app)
        .environment(ChatEngine(app: app))
        .modelContainer(PreviewData.container())
}
#endif
