import XCTest
@testable import DietCloud

final class AppConfigTests: XCTestCase {
    func testLoadValidDictionary() throws {
        let config = try AppConfigLoader.load(from: [
            "SUPABASE_URL": "https://abc.supabase.co",
            "SUPABASE_ANON_KEY": "anon-public-key",
            "API_BASE_URL": "https://diet-cloud.vercel.app",
            "STORAGE_BUCKET": "meal-photos",
        ])

        XCTAssertEqual(config.supabaseURL.host, "abc.supabase.co")
        XCTAssertEqual(config.supabaseAnonKey, "anon-public-key")
        XCTAssertEqual(config.apiBaseURL.host, "diet-cloud.vercel.app")
        XCTAssertEqual(config.storageBucket, "meal-photos")
        XCTAssertTrue(config.isReadyForNetwork)
        XCTAssertFalse(config.isPlaceholder)
    }

    func testPlaceholderDetection() throws {
        let config = try AppConfigLoader.load(from: [
            "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
            "SUPABASE_ANON_KEY": "YOUR_SUPABASE_ANON_KEY",
            "API_BASE_URL": "https://diet-cloud.vercel.app",
            "STORAGE_BUCKET": "meal-photos",
        ])

        XCTAssertTrue(config.isPlaceholder)
        XCTAssertFalse(config.isReadyForNetwork)
    }

    func testMissingKeyThrows() {
        XCTAssertThrowsError(
            try AppConfigLoader.load(from: [
                "SUPABASE_URL": "https://abc.supabase.co",
                "API_BASE_URL": "https://diet-cloud.vercel.app",
                "STORAGE_BUCKET": "meal-photos",
            ])
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError")
            }
            XCTAssertEqual(appError.code, "configuration")
            if case .configuration(.missingKey(let key)) = appError {
                XCTAssertEqual(key, "SUPABASE_ANON_KEY")
            } else {
                XCTFail("Expected missingKey")
            }
        }
    }

    func testInvalidURLThrows() {
        XCTAssertThrowsError(
            try AppConfigLoader.load(from: [
                "SUPABASE_URL": "not a url",
                "SUPABASE_ANON_KEY": "anon",
                "API_BASE_URL": "https://diet-cloud.vercel.app",
                "STORAGE_BUCKET": "meal-photos",
            ])
        ) { error in
            guard let appError = error as? AppError else {
                return XCTFail("Expected AppError")
            }
            if case .configuration(.invalidURL(let key, _)) = appError {
                XCTAssertEqual(key, "SUPABASE_URL")
            } else {
                XCTFail("Expected invalidURL, got \(appError)")
            }
        }
    }
}
