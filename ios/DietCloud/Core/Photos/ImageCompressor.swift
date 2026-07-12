import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Upload-ready JPEG payload (no secrets).
struct CompressedImage: Equatable, Sendable {
    let data: Data
    let contentType: String
    let fileName: String
    let width: Int
    let height: Int
}

enum ImageCompressor {
    /// Web targets ~300KB; we cap long edge and JPEG quality.
    static let maxLongEdge: CGFloat = 1600
    static let maxBytes = 300 * 1024
    static let allowedContentType = "image/jpeg"

    static func compressToJPEG(
        data: Data,
        preferredFileName: String = "meal.jpg"
    ) throws -> CompressedImage {
        guard !data.isEmpty else {
            throw AppError.unknown(message: "图片数据为空。")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw AppError.unknown(message: "无法读取所选图片。")
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw AppError.unknown(message: "无法解析图片属性。")
        }
        let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        guard pixelWidth > 0, pixelHeight > 0 else {
            throw AppError.unknown(message: "图片尺寸无效。")
        }

        let maxSide = max(pixelWidth, pixelHeight)
        let scale = min(1, Double(maxLongEdge) / maxSide)
        let targetWidth = max(1, Int((pixelWidth * scale).rounded()))
        let targetHeight = max(1, Int((pixelHeight * scale).rounded()))

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(targetWidth, targetHeight),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AppError.unknown(message: "图片压缩失败。")
        }

        var quality: CGFloat = 0.85
        var best: Data?
        for _ in 0 ..< 8 {
            let jpeg = try encodeJPEG(cgImage, quality: quality)
            best = jpeg
            if jpeg.count <= maxBytes { break }
            quality -= 0.1
            if quality < 0.35 { break }
        }
        guard let output = best, !output.isEmpty else {
            throw AppError.unknown(message: "无法生成 JPEG。")
        }

        let base = preferredFileName
            .replacingOccurrences(of: "\\.[^.]+$", with: "", options: .regularExpression)
        let safeBase = base.isEmpty ? "meal" : base
        return CompressedImage(
            data: output,
            contentType: allowedContentType,
            fileName: "\(safeBase).jpg",
            width: cgImage.width,
            height: cgImage.height
        )
    }

    private static func encodeJPEG(_ image: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw AppError.unknown(message: "JPEG 编码器不可用。")
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw AppError.unknown(message: "JPEG 编码失败。")
        }
        return data as Data
    }
}
