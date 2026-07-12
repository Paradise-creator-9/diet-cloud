import XCTest
@testable import DietCloud

final class MealPhotoRepositoryTests: XCTestCase {
    func testPathUsesSessionUserIdOnly() async throws {
        let userId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
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

    func testSignedURLRequestContainsNoSecrets() async throws {
        let repo = MockMealPhotoRepository()
        let request = SignedURLRequest(
            paths: ["u1/2026-07-12/a.jpg"],
            expiresIn: SignedURLRequest.defaultTTLSeconds
        )
        let refs = try await repo.signedURLs(for: request)
        XCTAssertEqual(repo.lastSignedRequest, request)
        XCTAssertEqual(refs.count, 1)
        XCTAssertFalse(refs[0].signedURL?.contains("service_role") == true)
        XCTAssertFalse(refs[0].signedURL?.contains("eyJhbGci") == true)
        // Fake URL is for tests only — no real token material.
        XCTAssertTrue(refs[0].signedURL?.contains("example.invalid") == true)
    }
}
