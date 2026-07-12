import Foundation

/// Photo metadata for a food item.
/// DB stores **paths** in `food_items.photo_urls` (name is historical).
/// Path convention: `{userId}/{dateKey}/{fileName}` under private bucket `meal-photos`.
struct MealPhotoRef: Equatable, Sendable, Identifiable {
    /// Storage object path (source of truth for persistence).
    let path: String
    /// Optional short-lived signed URL for display (not stored in DB).
    let signedURL: String?

    var id: String { path }

    /// First path segment should equal authenticated user id.
    var ownerUserId: String? {
        path.split(separator: "/").first.map(String.init)
    }

    var dateKeySegment: String? {
        let parts = path.split(separator: "/").map(String.init)
        return parts.count >= 2 ? parts[1] : nil
    }
}

enum MealPhotoPath {
    /// Builds a path under the current user's folder — caller must pass session userId.
    static func make(userId: String, dateKey: String, fileName: String, timestampMs: Int64) -> String {
        let safe = fileName.replacingOccurrences(
            of: "[^a-zA-Z0-9._-]",
            with: "-",
            options: .regularExpression
        )
        return "\(userId)/\(dateKey)/\(timestampMs)-\(safe)"
    }

    /// Reject paths that attempt to write outside the session user's folder.
    static func isOwned(path: String, byUserId userId: String) -> Bool {
        path.hasPrefix("\(userId)/")
    }
}

/// Parameters for requesting signed URLs — never includes API secrets.
struct SignedURLRequest: Equatable, Sendable {
    let paths: [String]
    /// Seconds; Web uses 24h (`PHOTO_SIGNED_URL_TTL_SECONDS`).
    let expiresIn: Int

    static let defaultTTLSeconds = 60 * 60 * 24
}
