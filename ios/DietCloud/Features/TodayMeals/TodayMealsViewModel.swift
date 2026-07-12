import Foundation
import Observation
import UIKit

enum TodayMealsLoadState: Equatable, Sendable {
    case loading
    case empty
    case loaded
    case error(String)
}

@MainActor
@Observable
final class TodayMealsViewModel {
    private(set) var loadState: TodayMealsLoadState = .loading
    private(set) var items: [FoodItem] = []
    private(set) var errorMessage: String?
    private(set) var isMutating = false

    /// Draft fields for add form (bound from view).
    var draftName = ""
    var draftMeal: MealType = .breakfast
    var draftCalories = ""
    var draftProtein = ""
    var draftCarbs = ""
    var draftFat = ""
    var draftGrams = ""
    var draftNote = ""
    var isPresentingAddSheet = false

    /// Optional JPEG-ready image chosen in the add sheet (not a secret).
    private(set) var draftPhotoData: Data?
    private(set) var draftPhotoPreview: UIImage?
    private(set) var isPreparingPhoto = false

    let dateKey: String
    let user: AuthUser

    private let foodRepository: FoodItemRepositoryProtocol
    private let photoRepository: MealPhotoRepositoryProtocol
    private let diaryCalendar: DiaryCalendar

    var summary: DailyNutritionSummary {
        foodRepository.nutritionSummary(for: items)
    }

    /// All meal slots in Web display order (empty sections included when loaded).
    var mealSections: [MealGroup] {
        MealType.displayOrder.map { meal in
            let filtered = items.filter { $0.meal == meal }
            return MealGroup(dateKey: dateKey, meal: meal, items: filtered)
        }
    }

    init(
        user: AuthUser,
        foodRepository: FoodItemRepositoryProtocol,
        photoRepository: MealPhotoRepositoryProtocol,
        diaryCalendar: DiaryCalendar = DiaryCalendar(),
        dateKey: String? = nil
    ) {
        self.user = user
        self.foodRepository = foodRepository
        self.photoRepository = photoRepository
        self.diaryCalendar = diaryCalendar
        self.dateKey = dateKey ?? diaryCalendar.dateKey()
    }

    func load() async {
        loadState = .loading
        errorMessage = nil
        do {
            let fetched = try await foodRepository.fetchByDateKey(dateKey)
            items = fetched
            loadState = fetched.isEmpty ? .empty : .loaded
        } catch {
            let mapped = DataErrorMapping.map(error)
            errorMessage = mapped.userMessage
            loadState = .error(mapped.userMessage)
            items = []
        }
    }

    func openAddSheet(defaultMeal: MealType = .breakfast) {
        draftMeal = defaultMeal
        draftName = ""
        draftCalories = ""
        draftProtein = ""
        draftCarbs = ""
        draftFat = ""
        draftGrams = ""
        draftNote = ""
        clearDraftPhoto()
        errorMessage = nil
        isPresentingAddSheet = true
    }

    func cancelAdd() {
        isPresentingAddSheet = false
        clearDraftPhoto()
        errorMessage = nil
    }

    func clearDraftPhoto() {
        draftPhotoData = nil
        draftPhotoPreview = nil
    }

    func reportUserFacingError(_ message: String) {
        errorMessage = message
    }

    /// Compresses picker data to JPEG before upload (HEIC → JPEG).
    func setDraftPhoto(rawData: Data) async {
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        do {
            let compressed = try ImageCompressor.compressToJPEG(data: rawData, preferredFileName: "meal.jpg")
            draftPhotoData = compressed.data
            draftPhotoPreview = UIImage(data: compressed.data)
            errorMessage = nil
        } catch {
            clearDraftPhoto()
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    func saveNewItem() async {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "请填写食物名称。"
            return
        }

        isMutating = true
        defer { isMutating = false }

        do {
            var photoPaths: [String] = []
            if let photoData = draftPhotoData {
                let uploaded = try await photoRepository.upload(
                    dateKey: dateKey,
                    fileName: "meal.jpg",
                    data: photoData,
                    contentType: ImageCompressor.allowedContentType
                )
                photoPaths = [uploaded.path]
            }

            let write = FoodItemWrite(
                dateKey: dateKey,
                meal: draftMeal,
                name: name,
                grams: parseNumber(draftGrams),
                calories: parseNumber(draftCalories),
                protein: parseNumber(draftProtein),
                carbs: parseNumber(draftCarbs),
                fat: parseNumber(draftFat),
                fiber: 0,
                note: draftNote.trimmingCharacters(in: .whitespacesAndNewlines),
                photoPaths: photoPaths
            )

            _ = try await foodRepository.create(write)
            isPresentingAddSheet = false
            clearDraftPhoto()
            errorMessage = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    func deleteItem(_ item: FoodItem) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await foodRepository.delete(id: item.id)
            errorMessage = nil
            await load()
        } catch {
            errorMessage = DataErrorMapping.map(error).userMessage
        }
    }

    private func parseNumber(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value >= 0 else {
            return 0
        }
        return value
    }
}
