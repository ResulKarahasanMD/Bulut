import SwiftUI
import UIKit

/// Shows a message in a read-only UITextView so any part of it can be selected and copied.
struct SelectableTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: text)
                .navigationTitle("Metni seç")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Bitti") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Tümünü kopyala") {
                            UIPasteboard.general.string = text
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct SelectableTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.font = UIFont.preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        view.backgroundColor = .systemBackground
        view.dataDetectorTypes = [.link]
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            view.text = text
        }
    }
}
