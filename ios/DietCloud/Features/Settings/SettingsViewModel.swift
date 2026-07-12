import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private(set) var errorMessage: String?
    private(set) var statusMessage: String?
    var isPresentingSignOutConfirm = false

    var draftCalories = ""
    var draftWeight = ""
    var draftProtein = ""
    var draftCarbs = ""
    var draftFat = ""

    let user: AuthUser
    private let goalsStore: GoalsStoring
    private let onSignOut: () -> Void

    init(user: AuthUser, goalsStore: GoalsStoring, onSignOut: @escaping () -> Void) {
        self.user = user
        self.goalsStore = goalsStore
        self.onSignOut = onSignOut
        loadDraftsFromStore()
    }

    func loadDraftsFromStore() {
        let g = goalsStore.goals
        draftCalories = Self.formatOptional(g.dailyCaloriesKcal)
        draftWeight = Self.formatOptional(g.targetWeightKg)
        draftProtein = Self.formatOptional(g.proteinGrams)
        draftCarbs = Self.formatOptional(g.carbsGrams)
        draftFat = Self.formatOptional(g.fatGrams)
        errorMessage = nil
        statusMessage = nil
    }

    /// Saves validated goals to local store. Empty fields clear that goal.
    @discardableResult
    func saveGoals() -> Bool {
        errorMessage = nil
        statusMessage = nil
        let (goals, message) = UserGoalsValidation.validate(
            caloriesText: draftCalories,
            weightText: draftWeight,
            proteinText: draftProtein,
            carbsText: draftCarbs,
            fatText: draftFat
        )
        if let goals {
            goalsStore.save(goals)
            loadDraftsFromStore()
            statusMessage = "目标已保存到本机。"
            return true
        }
        errorMessage = message ?? "输入无效，请检查后重试。"
        return false
    }

    func requestSignOut() {
        isPresentingSignOutConfirm = true
    }

    func cancelSignOut() {
        isPresentingSignOutConfirm = false
    }

    func confirmSignOut() {
        isPresentingSignOutConfirm = false
        onSignOut()
    }

    private static func formatOptional(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }
}
