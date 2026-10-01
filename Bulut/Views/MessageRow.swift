import SwiftUI
import UIKit

struct MessageRow: View {
    let message: ChatMessage
    let isStreaming: Bool
    let isLast: Bool
    var onRegenerate: () -> Void = {}

    @State private var isSelectingText = false

    var body: some View {
        Group {
            switch message.role {
            case .user:
                userBubble
            case .assistant, .system:
                assistantBody
            }
        }
        .sheet(isPresented: $isSelectingText) {
            SelectableTextSheet(text: message.content)
        }
    }

    // MARK: User

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .contextMenu {
                    copyButton
                    selectTextButton
                    ShareLink(item: message.content)
                }
        }
    }

    // MARK: Assistant

    private var assistantBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.thinking.isEmpty {
                ThinkingView(text: message.thinking, isActive: isStreaming && message.content.isEmpty)
            }

            if !message.content.isEmpty {
                MarkdownView(text: message.content)
            } else if isStreaming && message.thinking.isEmpty {
                TypingIndicator()
            }

            if let error = message.errorText {
                errorBox(error)
            }

            if !isStreaming && (!message.content.isEmpty || message.errorText != nil) {
                footer
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            if !message.content.isEmpty {
                copyButton
                selectTextButton
                ShareLink(item: message.content)
            }
            if isLast && !isStreaming {
                Button(action: onRegenerate) {
                    Label("Yeniden üret", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let model = message.modelName {
                Text(model)
            }
            if let speed = message.tokensPerSecond {
                Text("\(speed, specifier: "%.0f") tok/s")
            }
            Spacer()
            if !message.content.isEmpty {
                Button {
                    UIPasteboard.general.string = message.content
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Kopyala")
            }
            if isLast {
                Button(action: onRegenerate) {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Yeniden üret")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.borderless)
    }

    private func errorBox(_ error: String) -> some View {
        Label {
            Text(error)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .font(.callout)
        .foregroundStyle(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var selectTextButton: some View {
        Button {
            isSelectingText = true
        } label: {
            Label("Metni seç", systemImage: "selection.pin.in.out")
        }
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = message.content
        } label: {
            Label("Kopyala", systemImage: "doc.on.doc")
        }
    }
}

/// Collapsible reasoning trace for thinking models (e.g. gpt-oss, deepseek, kimi).
struct ThinkingView: View {
    let text: String
    let isActive: Bool
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                Text(isActive ? "Düşünüyor…" : "Düşünme süreci")
                if isActive {
                    ProgressView().controlSize(.mini)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct TypingIndicator: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .frame(width: 7, height: 7)
                    .opacity(dotOpacity(index))
            }
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
        .accessibilityLabel("Yanıt bekleniyor")
    }

    private func dotOpacity(_ index: Int) -> Double {
        let base = 0.25 + 0.75 * phase
        return index == 1 ? 1.25 - base : base
    }
}
