import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    let isStreaming: Bool
    let isEnabled: Bool
    var focus: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void

    private var canSend: Bool {
        isEnabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(isEnabled ? "Mesaj yaz" : "Önce bir model seç", text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused(focus)
                .disabled(!isEnabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))

            if isStreaming {
                Button(action: onStop) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 34))
                        .symbolRenderingMode(.hierarchical)
                }
                .accessibilityLabel("Durdur")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                }
                .disabled(!canSend)
                .accessibilityLabel("Gönder")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
