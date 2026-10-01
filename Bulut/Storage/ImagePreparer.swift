import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A picked photo, already downscaled: `data` goes to the model, `thumbnail` is shown in the chat.
struct PreparedImage: Identifiable, Sendable {
    let id = UUID()
    let data: Data
    let thumbnail: Data
}

/// Turns any photo ImageIO can read (HEIC, JPEG, PNG…) into small JPEGs. Pure ImageIO, so it runs
/// off the main thread and also on macOS for tests.
enum ImagePreparer {
    /// Long edge of the image sent to the model. Vision models downsample anyway; this keeps requests small.
    static let maxPixelSize = 1536
    static let thumbnailPixelSize = 360

    static func prepare(_ data: Data) -> PreparedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let full = downscaled(source, maxPixelSize: maxPixelSize),
              let small = downscaled(source, maxPixelSize: thumbnailPixelSize),
              let fullJPEG = jpeg(full, quality: 0.8),
              let smallJPEG = jpeg(small, quality: 0.7)
        else { return nil }
        return PreparedImage(data: fullJPEG, thumbnail: smallJPEG)
    }

    /// Applies the EXIF orientation and never upscales.
    private static func downscaled(_ source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
