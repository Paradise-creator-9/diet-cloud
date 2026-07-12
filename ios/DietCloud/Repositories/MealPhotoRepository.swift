import Foundation
import Supabase

/// Signed URL access for private `meal-photos` bucket.
/// Stage 2: no binary upload UI — path design + signed URL interface only.
protocol MealPhotoRepositoryProtocol: Sendable {
    func signedURLs(for request: SignedURLRequest) async throws -> [MealPhotoRef]
    func makePath(dateKey: String, fileName: String, timestampMs: Int64) async throws -> String
}

final class MealPhotoRepository: MealPhotoRepositoryProtocol, @unchecked Sendable {
    private let provider: SupabaseClientProviding
    private let identity: SessionIdentityProviding
    private let bucket: String

    init(
        provider: SupabaseClientProviding,
        identity: SessionIdentityProviding,
        bucket: String? = nil
    ) {
        self.provider = provider
        self.identity = identity
        self.bucket = bucket ?? provider.config.storageBucket
    }

    func makePath(dateKey: String, fileName: String, timestampMs: Int64) async throws -> String {
        let userId = try await identity.requireUserId()
        return MealPhotoPath.make(
            userId: userId,
            dateKey: dateKey,
            fileName: fileName,
            timestampMs: timestampMs
        )
    }

    func signedURLs(for request: SignedURLRequest) async throws -> [MealPhotoRef] {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
        let userId = try await identity.requireUserId()
        // Only sign paths owned by the session user (matches Storage RLS folder rule).
        let owned = request.paths.filter { MealPhotoPath.isOwned(path: $0, byUserId: userId) }
        if owned.isEmpty {
            return request.paths.map { MealPhotoRef(path: $0, signedURL: passThroughIfAbsolute($0)) }
        }
        do {
            let results = try await client.storage
                .from(bucket)
                .createSignedURLs(paths: owned, expiresIn: request.expiresIn)
            var map: [String: String] = [:]
            for result in results {
                if case .success(let path, let signedURL) = result {
                    map[path] = signedURL.absoluteString
                }
            }
            return request.paths.map { path in
                if let url = map[path] {
                    return MealPhotoRef(path: path, signedURL: url)
                }
                return MealPhotoRef(path: path, signedURL: passThroughIfAbsolute(path))
            }
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    private func passThroughIfAbsolute(_ path: String) -> String? {
        if path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("/") {
            return path
        }
        return nil
    }
}

final class MockMealPhotoRepository: MealPhotoRepositoryProtocol, @unchecked Sendable {
    let sessionUserId: String
    private(set) var lastSignedRequest: SignedURLRequest?

    init(sessionUserId: String = "11111111-1111-1111-1111-111111111111") {
        self.sessionUserId = sessionUserId
    }

    func makePath(dateKey: String, fileName: String, timestampMs: Int64) async throws -> String {
        MealPhotoPath.make(
            userId: sessionUserId,
            dateKey: dateKey,
            fileName: fileName,
            timestampMs: timestampMs
        )
    }

    func signedURLs(for request: SignedURLRequest) async throws -> [MealPhotoRef] {
        lastSignedRequest = request
        // Fake signed URLs — never real tokens.
        return request.paths.map { path in
            if path.hasPrefix("http") {
                return MealPhotoRef(path: path, signedURL: path)
            }
            return MealPhotoRef(path: path, signedURL: "https://example.invalid/signed/\(path)?exp=\(request.expiresIn)")
        }
    }
}
