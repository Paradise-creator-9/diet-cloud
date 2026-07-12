import Foundation

/// Rolling window for the meal photo library (includes today for day ranges).
enum PhotoLibraryRange: String, CaseIterable, Identifiable, Sendable {
    case days7
    case days30
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .days7: return "近 7 天"
        case .days30: return "近 30 天"
        case .all: return "全部"
        }
    }

    /// Day count for bounded ranges; `nil` means fetch all then cap by photo count.
    var dayCount: Int? {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .all: return nil
        }
    }
}

/// One grid cell: a single storage path linked to a food row.
struct PhotoLibraryItem: Equatable, Identifiable, Sendable {
    /// Stable id: `foodId|path`.
    let id: String
    let foodId: String
    let path: String
    let dateKey: String
    let meal: MealType
    let name: String
    let grams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let note: String
    let createdAt: String
    /// Display URL after signing (or absolute pass-through). `nil` = failed / not yet signed.
    var signedURL: String?

    var hasDisplayURL: Bool {
        guard let signedURL, !signedURL.isEmpty else { return false }
        return true
    }

    static func makeId(foodId: String, path: String) -> String {
        "\(foodId)|\(path)"
    }

    static func from(food: FoodItem, path: String, signedURL: String? = nil) -> PhotoLibraryItem {
        PhotoLibraryItem(
            id: makeId(foodId: food.id, path: path),
            foodId: food.id,
            path: path,
            dateKey: food.dateKey,
            meal: food.meal,
            name: food.name,
            grams: food.grams,
            calories: food.calories,
            protein: food.protein,
            carbs: food.carbs,
            fat: food.fat,
            fiber: food.fiber,
            note: food.note,
            createdAt: food.createdAt,
            signedURL: signedURL
        )
    }
}

/// Date section for the grid (newest day first).
struct PhotoLibrarySection: Equatable, Identifiable, Sendable {
    let dateKey: String
    let items: [PhotoLibraryItem]

    var id: String { dateKey }
}

/// Snapshot after a load attempt (metadata always present when non-empty).
struct PhotoLibrarySnapshot: Equatable, Sendable {
    var range: PhotoLibraryRange
    var items: [PhotoLibraryItem]
    var sections: [PhotoLibrarySection]
    /// Paths that still lack a display URL after signing.
    var failedPaths: [String]
    /// Soft cap applied (e.g. 全部 top 100).
    var wasCapped: Bool
    var startDateKey: String?
    var endDateKey: String?

    var totalCount: Int { items.count }
    var signedCount: Int { items.filter(\.hasDisplayURL).count }
    var failedCount: Int { failedPaths.count }
}

enum PhotoLibraryLoadState: Equatable, Sendable {
    case loading
    case loaded(PhotoLibrarySnapshot)
    case partial(PhotoLibrarySnapshot, message: String)
    case empty(PhotoLibrarySnapshot)
    case error(String)
}

/// Pure builders for flatten / sort / cap (unit-testable, no I/O).
enum PhotoLibraryBuilder {
    /// Soft max for「全部」(and safety net for large windows).
    static let maxPhotos = 100

    /// Flatten foods → one item per photo path. Empty paths skipped.
    /// Duplicate `(foodId, path)` pairs are collapsed so grid ids stay unique.
    /// Absolute URL paths are kept as metadata paths (display via pass-through at sign time).
    static func flatten(foods: [FoodItem]) -> [PhotoLibraryItem] {
        var result: [PhotoLibraryItem] = []
        var seenIds = Set<String>()
        for food in foods {
            for raw in food.photoPaths {
                let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !path.isEmpty else { continue }
                let id = PhotoLibraryItem.makeId(foodId: food.id, path: path)
                guard seenIds.insert(id).inserted else { continue }
                result.append(PhotoLibraryItem.from(food: food, path: path, signedURL: nil))
            }
        }
        return result
    }

    /// Sort: dateKey desc, then createdAt desc, then path asc for stability.
    static func sorted(_ items: [PhotoLibraryItem]) -> [PhotoLibraryItem] {
        items.sorted { lhs, rhs in
            if lhs.dateKey != rhs.dateKey { return lhs.dateKey > rhs.dateKey }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.path < rhs.path
        }
    }

    /// Apply soft cap after sort (newest first).
    static func capped(_ items: [PhotoLibraryItem], limit: Int = maxPhotos) -> (items: [PhotoLibraryItem], wasCapped: Bool) {
        if items.count <= limit {
            return (items, false)
        }
        return (Array(items.prefix(limit)), true)
    }

    static func sections(from items: [PhotoLibraryItem]) -> [PhotoLibrarySection] {
        var order: [String] = []
        var buckets: [String: [PhotoLibraryItem]] = [:]
        for item in items {
            if buckets[item.dateKey] == nil {
                order.append(item.dateKey)
                buckets[item.dateKey] = []
            }
            buckets[item.dateKey, default: []].append(item)
        }
        return order.map { key in
            PhotoLibrarySection(dateKey: key, items: buckets[key] ?? [])
        }
    }

    /// Inclusive start/end for day windows ending on `endDateKey` (includes today).
    static func bounds(
        for range: PhotoLibraryRange,
        endingOn endDateKey: String,
        calendar: DiaryCalendar
    ) -> (start: String, end: String)? {
        switch range {
        case .all:
            return nil
        case .days7, .days30:
            let count = range.dayCount ?? 7
            // Reuse trends math: last `count` days including end.
            let trend: TrendRange = count == 30 ? .days30 : .days7
            return TrendAggregator.startAndEndKeys(for: trend, endingOn: endDateKey, calendar: calendar)
        }
    }

    static func applySignedURLs(
        items: [PhotoLibraryItem],
        refs: [MealPhotoRef]
    ) -> [PhotoLibraryItem] {
        var map: [String: String] = [:]
        for ref in refs {
            if let url = ref.signedURL, !url.isEmpty {
                map[ref.path] = url
            }
        }
        return items.map { item in
            var copy = item
            if let url = map[item.path] {
                copy.signedURL = url
            } else if isAbsoluteDisplayPath(item.path) {
                // Absolute / http(s) paths: existing pass-through behavior.
                copy.signedURL = item.path
            } else {
                copy.signedURL = nil
            }
            return copy
        }
    }

    static func isAbsoluteDisplayPath(_ path: String) -> Bool {
        path.hasPrefix("http://") || path.hasPrefix("https://") || path.hasPrefix("/")
    }
}
