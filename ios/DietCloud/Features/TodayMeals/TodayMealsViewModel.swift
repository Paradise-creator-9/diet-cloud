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

    /// AI analysis in progress (does not write DB).
    private(set) var isAnalyzing = false
    /// Short success summary after AI fill (not an error).
    private(set) var analysisSummary: String?

    let dateKey: String
    let user: AuthUser

    private let foodRepository: FoodItemRepositoryProtocol
    private let photoRepository: MealPhotoRepositoryProtocol
    private let analyzeAPI: AnalyzeAPIClienting
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

    /// True when user provided enough input for AI (hint and/or photo).
    var canRunAIAnalysis: Bool {
        let hasHint = !draftNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasPhoto = draftPhotoData != nil
        return (hasHint || hasPhoto) && !isAnalyzing && !isPreparingPhoto && !isMutating
    }

    init(
        user: AuthUser,
        foodRepository: FoodItemRepositoryProtocol,
        photoRepository: MealPhotoRepositoryProtocol,
        analyzeAPI: AnalyzeAPIClienting,
        diaryCalendar: DiaryCalendar = DiaryCalendar(),
        dateKey: String? = nil
    ) {
        self.user = user
        self.foodRepository = foodRepository
        self.photoRepository = photoRepository
        self.analyzeAPI = analyzeAPI
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
        analysisSummary = nil
        isPresentingAddSheet = true
    }

    func cancelAdd() {
        isPresentingAddSheet = false
        clearDraftPhoto()
        errorMessage = nil
        analysisSummary = nil
    }

    func clearDraftPhoto() {
        draftPhotoData = nil
        draftPhotoPreview = nil
    }

    func reportUserFacingError(_ message: String) {
        errorMessage = message
    }

    /// Compresses picker data to JPEG before upload / AI (HEIC → JPEG).
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

    /// Calls `/api/analyze-meal` and fills draft fields only — does **not** save.
    func runAIAnalysis() async {
        errorMessage = nil
        analysisSummary = nil

        let hint = preferredAIHint()
        guard canRunAIAnalysis || (!hint.isEmpty || draftPhotoData != nil) else {
            errorMessage = "请先选择照片，或者至少写一句文字说明。"
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let request = try MealAnalysisRequest.make(
                hint: hint,
                jpegData: draftPhotoData,
                contentType: ImageCompressor.allowedContentType,
                fileName: "meal.jpg"
            )
            let result = try await analyzeAPI.analyzeMeal(request)
            applyAnalysisToDraft(result, userHint: hint)
        } catch {
            let mapped = mapAnalyzeError(error)
            errorMessage = mapped.userMessage
            // Do not clear draft fields on failure — manual entry still works.
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
            analysisSummary = nil
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

    // MARK: - AI helpers

    /// Prefer dedicated note as hint; fall back to draft name if it looks like a description.
    private func preferredAIHint() -> String {
        let note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        return draftName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyAnalysisToDraft(_ result: MealAnalysisResult, userHint: String) {
        let fill = MealAnalysisMapper.formFill(from: result, userHint: userHint)
        draftName = fill.name
        draftCalories = fill.calories
        draftProtein = fill.protein
        draftCarbs = fill.carbs
        draftFat = fill.fat
        draftGrams = fill.grams
        draftNote = fill.note
        analysisSummary = fill.summary
        errorMessage = nil
        // meal type left as user selection; API does not return mealType.
    }

    private func mapAnalyzeError(_ error: Error) -> AppError {
        if let app = error as? AppError {
            // Soften rate-limit copy for AI context without leaking details.
            if case .rateLimited = app {
                return .rateLimited(retryAfterSeconds: nil)
            }
            return app
        }
        return DataErrorMapping.map(error)
    }

    private func parseNumber(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value >= 0 else {
            return 0
        }
        return value
    }
}
