import Foundation

/// Local favorite-food templates (UserDefaults / in-memory for tests). No secrets / no cloud.
protocol FavoriteFoodsStoring: AnyObject, Sendable {
    var favorites: [FavoriteFood] { get }
    func save(_ favorites: [FavoriteFood])
    func reload()
}

/// Thread-safe UserDefaults-backed favorites store.
final class UserDefaultsFavoriteFoodsStore: FavoriteFoodsStoring, @unchecked Sendable {
    static let storageKey = "dietcloud.favoriteFoods.v1"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var _favorites: [FavoriteFood]

    var favorites: [FavoriteFood] {
        lock.lock(); defer { lock.unlock() }
        return _favorites
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self._favorites = Self.load(from: defaults)
    }

    func save(_ favorites: [FavoriteFood]) {
        lock.lock()
        _favorites = favorites
        lock.unlock()
        if let data = try? JSONEncoder().encode(favorites) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    func reload() {
        let loaded = Self.load(from: defaults)
        lock.lock()
        _favorites = loaded
        lock.unlock()
    }

    /// Missing / corrupt data → empty list (never crashes, no seed defaults).
    /// Corrupt payloads are removed so subsequent launches stay clean.
    private static func load(from defaults: UserDefaults) -> [FavoriteFood] {
        guard let data = defaults.data(forKey: storageKey) else {
            return []
        }
        guard let decoded = try? JSONDecoder().decode([FavoriteFood].self, from: data) else {
            defaults.removeObject(forKey: storageKey)
            return []
        }
        return decoded
    }
}

/// In-memory store for unit tests.
final class InMemoryFavoriteFoodsStore: FavoriteFoodsStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var _favorites: [FavoriteFood]

    init(favorites: [FavoriteFood] = []) {
        self._favorites = favorites
    }

    var favorites: [FavoriteFood] {
        lock.lock(); defer { lock.unlock() }
        return _favorites
    }

    func save(_ favorites: [FavoriteFood]) {
        lock.lock()
        _favorites = favorites
        lock.unlock()
    }

    func reload() {}
}
