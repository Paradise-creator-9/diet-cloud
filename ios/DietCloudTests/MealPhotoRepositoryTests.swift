import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import DietCloud

final class MealPhotoRepositoryTests: XCTestCase {
    private let userId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    func testPathUsesSessionUserIdOnly() async throws {
        let repo = MockMealPhotoRepository(sessionUserId: userId)
        let path = try await repo.makePath(
            dateKey: "2026-07-12",
            fileName: "photo name!.jpg",
            timestampMs: 1_720_000_000_000
        )
        XCTAssertTrue(path.hasPrefix("\(userId)/2026-07-12/"))
        XCTAssertFalse(path.contains("!"))
        XCTAssertTrue(MealPhotoPath.isOwned(path: path, byUserId: userId))
        XCTAssertFalse(MealPhotoPath.isOwned(path: path, byUserId: "other"))
    }

    func testPathCannotBeBuiltForForeignUserViaHelper() {
        let foreign = MealPhotoPath.make(
            userId: "other-user",
            dateKey: "2026-07-12",
            fileName: "x.jpg",
            timestampMs: 1
        )
        XCTAssertFalse(MealPhotoPath.isOwned(path: foreign, byUserId: userId))
    }

    func testUploadRecordsJPEGMimeAndOwnedPath() async throws {
        let repo = MockMealPhotoRepository(sessionUserId: userId)
        let data = Data(repeating: 0xFF, count: 64)
        let ref = try await repo.upload(
            dateKey: "2026-07-13",
            fileName: "meal.jpg",
            data: data,
            contentType: "image/jpeg"
        )
        XCTAssertTrue(ref.path.hasPrefix("\(userId)/2026-07-13/"))
        XCTAssertEqual(repo.lastUploadContentType, "image/jpeg")
        XCTAssertEqual(repo.lastUploadByteCount, 64)
        XCTAssertNotNil(ref.signedURL)
        XCTAssertTrue(ref.signedURL?.contains("example.invalid") == true)
        XCTAssertFalse(ref.signedURL?.contains("eyJ") == true)
    }

    func testSignedURLRequestContainsNoSecrets() async throws {
        let repo = MockMealPhotoRepository(sessionUserId: userId)
        let request = SignedURLRequest(
            paths: ["\(userId)/2026-07-12/a.jpg"],
            expiresIn: SignedURLRequest.defaultTTLSeconds
        )
        let refs = try await repo.signedURLs(for: request)
        XCTAssertEqual(repo.lastSignedRequest, request)
        XCTAssertEqual(refs.count, 1)
        XCTAssertFalse(refs[0].signedURL?.contains("service_role") == true)
        XCTAssertFalse(refs[0].signedURL?.contains("eyJhbGci") == true)
        XCTAssertTrue(refs[0].signedURL?.contains("example.invalid") == true)
    }

    func testDeleteOnlySessionOwnedPaths() async throws {
        let repo = MockMealPhotoRepository(sessionUserId: userId)
        try await repo.delete(paths: [
            "\(userId)/2026-07-12/a.jpg",
            "other/2026-07-12/b.jpg",
        ])
        XCTAssertEqual(repo.deletedPaths, ["\(userId)/2026-07-12/a.jpg"])
    }

    func testDeleteFailureMapsSafely() async {
        let repo = MockMealPhotoRepository(sessionUserId: userId)
        repo.forcedError = AppError.auth(.provider(message: "token eyJhbGciOiJIUzI1NiJ9.payload.sig"))
        do {
            try await repo.delete(paths: ["\(userId)/x.jpg"])
            XCTFail("expected error")
        } catch {
            let mapped = DataErrorMapping.map(error)
            XCTAssertFalse(mapped.userMessage.contains("eyJ"))
        }
    }

    func testImageCompressorProducesJPEGUnderCap() throws {
        // Synthetic solid color image via compressor path with tiny JPEG input.
        let tiny = Self.solidJPEG()
        let compressed = try ImageCompressor.compressToJPEG(data: tiny, preferredFileName: "meal.heic")
        XCTAssertEqual(compressed.contentType, "image/jpeg")
        XCTAssertTrue(compressed.fileName.hasSuffix(".jpg"))
        XCTAssertLessThanOrEqual(compressed.data.count, ImageCompressor.maxBytes)
        XCTAssertGreaterThan(compressed.width, 0)
        XCTAssertGreaterThan(compressed.height, 0)
    }

    func testImageCompressorRejectsEmptyData() {
        XCTAssertThrowsError(try ImageCompressor.compressToJPEG(data: Data()))
    }

    /// Programmatic solid-color JPEG so ImageIO can read real pixel dimensions.
    private static func solidJPEG(width: Int = 32, height: Int = 32) -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("CGContext unavailable for test JPEG")
        }
        ctx.setFillColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = ctx.makeImage() else {
            fatalError("CGImage unavailable for test JPEG")
        }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            fatalError("JPEG destination unavailable")
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            fatalError("JPEG finalize failed")
        }
        return data as Data
    }
}
