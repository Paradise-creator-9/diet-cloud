import Foundation
import Observation

@MainActor
@Observable
final class PhotoLibraryViewModel {
    private(set) var loadState: PhotoLibraryLoadState = .loading
    private(set) var range: PhotoLibraryRange = .days7
    /// Currently presented detail (sheet).
    private(set) var selectedItem: PhotoLibraryItem?
    var isPresentingDetail = false
    /// Per-path retry in progress.
    private(set) var retryingPath: String?

    private let foodRepository: FoodItemRepositoryProtocol
    private let photoRepository: MealPhotoRepositoryProtocol
    private let diaryCalendar: DiaryCalendar
    private let nowProvider: () -> Date
    private var loadGeneration = 0

    init(
        foodRepository: FoodItemRepositoryProtocol,
        photoRepository: MealPhotoRepositoryProtocol,
        diaryCalendar: DiaryCalendar = DiaryCalendar(),
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.foodRepository = foodRepository
        self.photoRepository = photoRepository
        self.diaryCalendar = diaryCalendar
        self.nowProvider = nowProvider
    }

    var navigationTitle: String { "照片库" }

    func selectRange(_ newRange: PhotoLibraryRange) async {
        guard newRange != range else { return }
        range = newRange
        await load()
    }

    func retry() async {
        await load()
    }

    func openDetail(_ item: PhotoLibraryItem) {
        selectedItem = item
        isPresentingDetail = true
    }

    func closeDetail() {
        isPresentingDetail = false
        selectedItem = nil
    }

    /// Re-sign a single path (detail / tile retry). Never re-fetches foods, never writes/uploads.
    func retrySign(for item: PhotoLibraryItem) async {
        guard retryingPath == nil else { return }
        retryingPath = item.path
        defer { retryingPath = nil }

        do {
            let refs = try await photoRepository.signedURLs(
                for: SignedURLRequest(
                    paths: [item.path],
                    expiresIn: SignedURLRequest.defaultTTLSeconds
                )
            )
            let url = refs.first?.signedURL
                ?? (PhotoLibraryBuilder.isAbsoluteDisplayPath(item.path) ? item.path : nil)
            applyURL(url, toItemId: item.id)
            if selectedItem?.id == item.id {
                var updated = item
                updated.signedURL = url
                selectedItem = updated
            }
        } catch {
            // Keep previous metadata; surface message via partial if we have a snapshot.
            if let snap = currentSnapshot {
                let message = DataErrorMapping.map(error).userMessage
                loadState = .partial(snap, message: message)
            }
        }
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        if currentSnapshot == nil {
            loadState = .loading
        }

        let endKey = diaryCalendar.dateKey(from: nowProvider())
        let bounds = PhotoLibraryBuilder.bounds(
            for: range,
            endingOn: endKey,
            calendar: diaryCalendar
        )

        let foods: [FoodItem]
        do {
            if let bounds {
                foods = try await foodRepository.fetchBetween(
                    startDateKey: bounds.start,
                    endDateKey: bounds.end
                )
            } else {
                foods = try await foodRepository.fetchAll()
            }
        } catch {
            guard generation == loadGeneration else { return }
            let message = DataErrorMapping.map(error).userMessage
            if let snap = currentSnapshot, !snap.items.isEmpty {
                loadState = .partial(snap, message: message)
            } else {
                loadState = .error(message)
            }
            return
        }

        guard generation == loadGeneration else { return }

        let flattened = PhotoLibraryBuilder.flatten(foods: foods)
        let sorted = PhotoLibraryBuilder.sorted(flattened)
        // Soft cap applies to「全部」only (newest 100 after sort). Day windows keep full range.
        let (capped, wasCapped): ([PhotoLibraryItem], Bool)
        if range == .all {
            (capped, wasCapped) = PhotoLibraryBuilder.capped(sorted)
        } else {
            (capped, wasCapped) = (sorted, false)
        }
        var base = PhotoLibrarySnapshot(
            range: range,
            items: capped,
            sections: PhotoLibraryBuilder.sections(from: capped),
            failedPaths: capped.map(\.path),
            wasCapped: wasCapped,
            startDateKey: bounds?.start,
            endDateKey: bounds?.end ?? endKey
        )

        if capped.isEmpty {
            loadState = .empty(base)
            return
        }

        // Sign independently so a total sign failure still keeps metadata.
        let paths = capped.map(\.path)
        do {
            let refs = try await photoRepository.signedURLs(
                for: SignedURLRequest(
                    paths: paths,
                    expiresIn: SignedURLRequest.defaultTTLSeconds
                )
            )
            guard generation == loadGeneration else { return }
            let signedItems = PhotoLibraryBuilder.applySignedURLs(items: capped, refs: refs)
            let failed = signedItems.filter { !$0.hasDisplayURL }.map(\.path)
            base.items = signedItems
            base.sections = PhotoLibraryBuilder.sections(from: signedItems)
            base.failedPaths = failed
            if failed.isEmpty {
                loadState = .loaded(base)
            } else {
                loadState = .partial(base, message: "部分照片无法加载，可点击重试。")
            }
        } catch {
            guard generation == loadGeneration else { return }
            // Keep all metadata; no display URLs.
            base.failedPaths = paths
            let message = DataErrorMapping.map(error).userMessage
            loadState = .partial(base, message: message.isEmpty ? "照片签名失败，可重试。" : message)
        }
    }

    var currentSnapshot: PhotoLibrarySnapshot? {
        switch loadState {
        case .loaded(let s), .partial(let s, _), .empty(let s):
            return s
        case .loading, .error:
            return nil
        }
    }

    private func applyURL(_ url: String?, toItemId id: String) {
        guard var snap = currentSnapshot else { return }
        snap.items = snap.items.map { item in
            guard item.id == id else { return item }
            var copy = item
            copy.signedURL = url
            return copy
        }
        snap.sections = PhotoLibraryBuilder.sections(from: snap.items)
        snap.failedPaths = snap.items.filter { !$0.hasDisplayURL }.map(\.path)
        if snap.failedPaths.isEmpty {
            loadState = .loaded(snap)
        } else {
            let msg: String
            if case .partial(_, let existing) = loadState {
                msg = existing
            } else {
                msg = "部分照片无法加载，可点击重试。"
            }
            loadState = .partial(snap, message: msg)
        }
    }
}
