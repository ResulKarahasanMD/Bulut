import PhotosUI
import SwiftUI
import UIKit

struct ComposerView: View {
    @Binding var text: String
    @Binding var images: [PreparedImage]
    let canAttachImages: Bool
    let isStreaming: Bool
    let isEnabled: Bool
    var focus: FocusState<Bool>.Binding
    let onSend: () -> Void
    let onStop: () -> Void

    static let maxImages = 4

    @State private var pickerItems: [PhotosPickerItem] = []
    /// One load at a time; cancelled when the model can no longer see images.
    @State private var loadTask: Task<Void, Never>?

    private var isPreparingImages: Bool { loadTask != nil }

    private var canSend: Bool {
        isEnabled && !isPreparingImages
            && (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !images.isEmpty || isPreparingImages {
                attachmentStrip
            }

            HStack(alignment: .bottom, spacing: 8) {
                if canAttachImages {
                    PhotosPicker(
                        selection: $pickerItems,
                        maxSelectionCount: max(Self.maxImages - images.count, 1),
                        matching: .images
                    ) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 22))
                            .frame(width: 34, height: 38)
                    }
                    .disabled(!isEnabled || isStreaming || isPreparingImages || images.count >= Self.maxImages)
                    .accessibilityLabel("Görsel ekle")
                }

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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .onChange(of: pickerItems) {
            let items = pickerItems
            guard !items.isEmpty, loadTask == nil else { return }
            pickerItems = []
            let task = Task { await load(items) }
            loadTask = task
            Task {
                await task.value
                // A cancelled load must not clear the handle of a newer one.
                if loadTask == task { loadTask = nil }
            }
        }
        .onChange(of: canAttachImages) {
            // Switched to a model that cannot see images: drop pending and in-flight photos.
            guard !canAttachImages else { return }
            loadTask?.cancel()
            loadTask = nil
            images = []
        }
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(images) { image in
                    ThumbnailView(data: image.thumbnail, side: 64)
                        .overlay(alignment: .topTrailing) {
                            Button {
                                images.removeAll { $0.id == image.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .offset(x: 6, y: -6)
                            .accessibilityLabel("Görseli kaldır")
                        }
                }
                if isPreparingImages {
                    ProgressView()
                        .frame(width: 64, height: 64)
                }
            }
            .padding(.top, 6)
            .padding(.trailing, 6)
        }
    }

    /// Loads the picked photos and downscales them off the main thread.
    private func load(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let raw = try? await item.loadTransferable(type: Data.self) else { continue }
            let prepared = await Task.detached(priority: .userInitiated) {
                ImagePreparer.prepare(raw)
            }.value
            // Re-check after each await: the load may have been cancelled or the strip filled up.
            guard !Task.isCancelled else { return }
            if let prepared, images.count < Self.maxImages {
                images.append(prepared)
            }
        }
    }
}

/// A square, cropped JPEG thumbnail.
struct ThumbnailView: View {
    let data: Data
    let side: CGFloat

    var body: some View {
        Group {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .background(Color(.tertiarySystemFill))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
