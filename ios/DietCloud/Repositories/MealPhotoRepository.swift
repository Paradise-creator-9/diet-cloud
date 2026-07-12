import Foundation
import Supabase

/// Private `meal-photos` bucket: path + upload + signed URL + delete.
/// Paths: `{userId}/{dateKey}/{timestamp}-{fileName}` (matches Web / Storage RLS).
protocol MealPhotoRepositoryProtocol: Sendable {
    func signedURLs(for request: SignedURLRequest) async throws -> [MealPhotoRef]
    func makePath(dateKey: String, fileName: String, timestampMs: Int64) async throws -> String
    /// Uploads JPEG (or allowed MIME) bytes; userId always from session.
    func upload(
        dateKey: String,
        fileName: String,
        data: Data,
        contentType: String
    ) async throws -> MealPhotoRef
    /// Removes objects owned by the session user only.
    func delete(paths: [String]) async throws
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

    func upload(
        dateKey: String,
        fileName: String,
        data: Data,
        contentType: String
    ) async throws -> MealPhotoRef {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
        guard !data.isEmpty else {
            throw AppError.unknown(message: "图片数据为空。")
        }
        let mime = contentType.isEmpty ? ImageCompressor.allowedContentType : contentType
        guard mime == "image/jpeg" || mime == "image/jpg" || mime == "image/png" || mime == "image/webp" else {
            throw AppError.unknown(message: "不支持的图片格式，请使用 JPEG。")
        }

        let userId = try await identity.requireUserId()
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        let path = MealPhotoPath.make(
            userId: userId,
            dateKey: dateKey,
            fileName: fileName,
            timestampMs: timestampMs
        )
        guard MealPhotoPath.isOwned(path: path, byUserId: userId) else {
            throw AppError.unauthorized
        }

        do {
            _ = try await client.storage
                .from(bucket)
                .upload(
                    path,
                    data: data,
                    options: FileOptions(cacheControl: "3600", contentType: mime, upsert: false)
                )
            let signed = try await signedURLs(
                for: SignedURLRequest(paths: [path], expiresIn: SignedURLRequest.defaultTTLSeconds)
            )
            return signed.first ?? MealPhotoRef(path: path, signedURL: nil)
        } catch {
            throw DataErrorMapping.map(error)
        }
    }

    func signedURLs(for request: SignedURLRequest) async throws -> [MealPhotoRef] {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
        let userId = try await identity.requireUserId()
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
                    // Store full URL for AsyncImage; never log query tokens.
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

    func delete(paths: [String]) async throws {
        guard provider.isConfigured, let client = provider.client else {
            throw AppError.auth(.notConfigured)
        }
        let userId = try await identity.requireUserId()
        let owned = paths.filter { MealPhotoPath.isOwned(path: $0, byUserId: userId) }
        guard !owned.isEmpty else { return }
        do {
            try await client.storage.from(bucket).remove(paths: owned)
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
    private(set) var lastUploadPath: String?
    private(set) var lastUploadContentType: String?
    private(set) var lastUploadByteCount: Int?
    private(set) var deletedPaths: [String] = []
    var forcedError: Error?
    /// Simulated object store for ownership checks.
    private var storedPaths: Set<String> = []

    init(sessionUserId: String = "11111111-1111-1111-1111-111111111111") {
        self.sessionUserId = sessionUserId
    }

    func makePath(dateKey: String, fileName: String, timestampMs: Int64) async throws -> String {
        try throwIfForced()
        return MealPhotoPath.make(
            userId: sessionUserId,
            dateKey: dateKey,
            fileName: fileName,
            timestampMs: timestampMs
        )
    }

    func upload(
        dateKey: String,
        fileName: String,
        data: Data,
        contentType: String
    ) async throws -> MealPhotoRef {
        try throwIfForced()
        let path = try await makePath(
            dateKey: dateKey,
            fileName: fileName,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        guard MealPhotoPath.isOwned(path: path, byUserId: sessionUserId) else {
            throw AppError.unauthorized
        }
        lastUploadPath = path
        lastUploadContentType = contentType
        lastUploadByteCount = data.count
        storedPaths.insert(path)
        return MealPhotoRef(
            path: path,
            signedURL: "https://example.invalid/signed/\(path)?exp=\(SignedURLRequest.defaultTTLSeconds)"
        )
    }

    func signedURLs(for request: SignedURLRequest) async throws -> [MealPhotoRef] {
        try throwIfForced()
        lastSignedRequest = request
        return request.paths.map { path in
            if path.hasPrefix("http") {
                return MealPhotoRef(path: path, signedURL: path)
            }
            return MealPhotoRef(
                path: path,
                signedURL: "https://example.invalid/signed/\(path)?exp=\(request.expiresIn)"
            )
        }
    }

    func delete(paths: [String]) async throws {
        try throwIfForced()
        let owned = paths.filter { MealPhotoPath.isOwned(path: $0, byUserId: sessionUserId) }
        deletedPaths.append(contentsOf: owned)
        owned.forEach { storedPaths.remove($0) }
    }

    private func throwIfForced() throws {
        if let forcedError { throw forcedError }
    }
}
