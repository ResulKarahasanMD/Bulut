import SwiftData
import SwiftUI

struct ChatView: View {
    @Bindable var conversation: Conversation

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(ChatEngine.self) private var engine

    @State private var draft = ""
    @State private var isEditingSystemPrompt = false
    @FocusState private var isComposerFocused: Bool

    private var isStreaming: Bool { engine.isStreaming(conversation) }

    var body: some View {
        let messages = conversation.sortedMessages
        let lastID = messages.last?.id

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(messages) { message in
                        MessageRow(
                            message: message,
                            isStreaming: isStreaming && message.id == lastID,
                            isLast: message.id == lastID,
                            onRegenerate: { engine.regenerate(in: conversation, context: context) }
                        )
                        .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            .onChange(of: messages.last?.content.count) {
                if isStreaming { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView(
                text: $draft,
                isStreaming: isStreaming,
                isEnabled: !conversation.modelName.isEmpty,
                focus: $isComposerFocused,
                onSend: send,
                onStop: { engine.stop(conversation) }
            )
        }
        .navigationTitle(conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { modelMenu }
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .sheet(isPresented: $isEditingSystemPrompt) {
            SystemPromptSheet(prompt: $conversation.systemPrompt)
        }
        .task {
            if app.modelNames.isEmpty { await app.refreshModels() }
        }
    }

    private static let bottomID = "bottom"

    // MARK: Pieces

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "cloud")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text(conversation.modelName.isEmpty ? "Yukarıdan bir model seç" : conversation.modelName)
                .font(.headline)
            if !conversation.systemPrompt.isEmpty {
                Text(conversation.systemPrompt)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private var modelMenu: some View {
        Menu {
            if app.modelNames.isEmpty {
                Text(app.modelsError ?? "Model listesi yükleniyor…")
            } else {
                Picker("Model", selection: $conversation.modelName) {
                    ForEach(app.modelNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
            }
            Divider()
            Button {
                Task { await app.refreshModels() }
            } label: {
                Label("Listeyi yenile", systemImage: "arrow.clockwise")
            }
            if !conversation.modelName.isEmpty && conversation.modelName != app.defaultModel {
                Button {
                    app.setDefaultModel(conversation.modelName)
                } label: {
                    Label("Varsayılan yap", systemImage: "star")
                }
            }
        } label: {
            VStack(spacing: 1) {
                Text(conversation.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Text(conversation.modelName.isEmpty ? "Model seç" : conversation.modelName)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 240)
        }
        .disabled(isStreaming)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                isEditingSystemPrompt = true
            } label: {
                Label("Sistem talimatı", systemImage: "text.quote")
            }
            ShareLink(item: conversation.transcript()) {
                Label("Sohbeti paylaş", systemImage: "square.and.arrow.up")
            }
            .disabled(conversation.sortedMessages.isEmpty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    // MARK: Actions

    private func send() {
        let text = draft
        draft = ""
        engine.send(text, in: conversation, context: context)
    }
}

struct SystemPromptSheet: View {
    @Binding var prompt: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $prompt)
                        .frame(minHeight: 220)
                } footer: {
                    Text("Bu sohbetteki her istekte modele en başta gönderilir. Rol, üslup ya da kurallar için kullan.")
                }
            }
            .navigationTitle("Sistem talimatı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Temizle", role: .destructive) { prompt = "" }
                        .disabled(prompt.isEmpty)
                }
            }
        }
    }
}
