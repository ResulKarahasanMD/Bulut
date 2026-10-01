import SwiftData
import SwiftUI

struct ChatView: View {
    @Bindable var conversation: Conversation

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(ChatEngine.self) private var engine

    @Query(sort: \Persona.createdAt) private var personas: [Persona]

    @State private var draft = ""
    @State private var pendingImages: [PreparedImage] = []
    @State private var isEditingSystemPrompt = false
    @State private var isShowingModelSettings = false
    @State private var editingMessage: ChatMessage?
    /// Follow a streaming reply only while you are at the bottom, so you can scroll up and read.
    @State private var isAtBottom = true
    @FocusState private var isComposerFocused: Bool

    private var isStreaming: Bool { engine.isStreaming(conversation) }
    private var details: ModelDetails? { app.modelDetails[conversation.modelName] }
    /// Only offered when `/api/show` confirmed the `vision` capability.
    private var canAttachImages: Bool { details?.supportsVision == true }

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
                            onRegenerate: { engine.regenerate(in: conversation, context: context) },
                            canEdit: !isStreaming,
                            onEdit: { editingMessage = message }
                        )
                        .id(message.id)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomID)
                        // iOS 17 fallback for `BottomTracking`, which measures the geometry on iOS 18+.
                        .onAppear {
                            if #unavailable(iOS 18) { isAtBottom = true }
                        }
                        .onDisappear {
                            if #unavailable(iOS 18) { isAtBottom = false }
                        }
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .modifier(BottomTracking(isAtBottom: $isAtBottom))
            .modifier(MessageScrollFeatures())
            .onChange(of: messages.count) {
                // A new message (yours or the start of a reply) always brings you down.
                withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
            // utf8.count is O(1) for native strings; this runs on every 50 ms flush.
            .onChange(of: messages.last?.content.utf8.count) {
                if isStreaming && isAtBottom { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView(
                text: $draft,
                images: $pendingImages,
                canAttachImages: canAttachImages,
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
            if #available(iOS 27, *) {
                ToolbarOverflowMenu { moreMenuItems }
            } else {
                ToolbarItem(placement: .topBarTrailing) { moreMenu }
            }
        }
        .sheet(isPresented: $isEditingSystemPrompt) {
            SystemPromptSheet(prompt: $conversation.systemPrompt)
        }
        .sheet(isPresented: $isShowingModelSettings) {
            ModelSettingsSheet(conversation: conversation, details: details)
        }
        .sheet(item: $editingMessage) { message in
            EditMessageSheet(initialText: message.content, allowsEmptyText: message.hasImages) { text in
                engine.resend(message, as: text, in: conversation, context: context)
            }
        }
        .task {
            if app.modelNames.isEmpty { await app.refreshModels() }
        }
        .task(id: conversation.modelName) {
            await app.loadDetails(for: conversation.modelName)
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

    /// Before iOS 27 the same items live in an explicit "…" menu.
    private var moreMenu: some View {
        Menu {
            moreMenuItems
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Diğer")
    }

    @ViewBuilder
    private var moreMenuItems: some View {
        Button {
            isShowingModelSettings = true
        } label: {
            Label("Model ayarları", systemImage: "slider.horizontal.3")
        }
        Menu {
            ForEach(personas) { persona in
                Button {
                    conversation.systemPrompt = persona.systemPrompt
                } label: {
                    if conversation.systemPrompt == persona.systemPrompt {
                        Label(persona.name, systemImage: "checkmark")
                    } else {
                        Text(persona.name)
                    }
                }
            }
            if !conversation.systemPrompt.isEmpty {
                Divider()
                Button("Personayı kaldır", role: .destructive) {
                    conversation.systemPrompt = ""
                }
            }
        } label: {
            Label("Persona", systemImage: "person.crop.rectangle.stack")
        }
        Button {
            isEditingSystemPrompt = true
        } label: {
            Label("Sistem talimatı", systemImage: "text.quote")
        }
        if isStreaming {
            // The body runs on every streamed flush; build the transcript only when it can be shared.
            Button {} label: {
                Label("Sohbeti paylaş", systemImage: "square.and.arrow.up")
            }
            .disabled(true)
        } else {
            ShareLink(item: conversation.transcript()) {
                Label("Sohbeti paylaş", systemImage: "square.and.arrow.up")
            }
            .disabled(conversation.messages?.isEmpty ?? true)
        }
    }

    // MARK: Actions

    private func send() {
        let text = draft
        let images = pendingImages
        draft = ""
        pendingImages = []
        engine.send(text, images: images, in: conversation, context: context)
    }
}

/// Keeps `isAtBottom` current from the scroll geometry on iOS 18+. On iOS 17 the bottom marker's
/// appear and disappear do the same job (see `ChatView`).
private struct BottomTracking: ViewModifier {
    @Binding var isAtBottom: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.visibleRect.maxY >= geometry.contentSize.height - 60
            } action: { _, atBottom in
                isAtBottom = atBottom
            }
        } else {
            content
        }
    }
}

/// iOS 27 only: the navigation bar shrinks while you scroll down to read, and message rows can be
/// swiped for their actions (`MessageRow` declares them; they have no effect before iOS 27).
private struct MessageScrollFeatures: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 27, *) {
            content
                .toolbarMinimizationBehavior(.onScrollDown, for: .navigationBar)
                .swipeActionsContainer()
        } else {
            content
        }
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

/// Edits a sent message; saving drops the replies after it and asks the model again.
struct EditMessageSheet: View {
    /// Image-only messages may be resent without text.
    let allowsEmptyText: Bool
    let onResend: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(initialText: String, allowsEmptyText: Bool = false, onResend: @escaping (String) -> Void) {
        self.allowsEmptyText = allowsEmptyText
        self.onResend = onResend
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 200)
                } footer: {
                    Text("Gönderince bu mesajdan sonraki yanıtlar silinir ve model yeniden yanıtlar.")
                }
            }
            .navigationTitle("Mesajı düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Gönder") {
                        onResend(text)
                        dismiss()
                    }
                    .disabled(!allowsEmptyText && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
