import Foundation
import Observation

@MainActor
@Observable
final class TrendsViewModel {
    private(set) var loadState: TrendsLoadState = .loading
    private(set) var range: TrendRange = .days7
    private(set) var selectedNutrient: TrendNutrientMetric = .protein
    private(set) var selectedActivityMetric: TrendActivityMetric = .steps

    private let foodRepository: FoodItemRepositoryProtocol
    private let bodyRepository: BodyMetricsRepositoryProtocol
    private let dailyActivityRepository: DailyActivityRepositoryProtocol
    private let exerciseRepository: ExerciseActivityRepositoryProtocol
    private let goalsStore: GoalsStoring
    private let diaryCalendar: DiaryCalendar
    /// Fixed "today" for tests; production uses live calendar.
    private let nowProvider: () -> Date

    private var loadGeneration = 0

    init(
        foodRepository: FoodItemRepositoryProtocol,
        bodyRepository: BodyMetricsRepositoryProtocol,
        dailyActivityRepository: DailyActivityRepositoryProtocol,
        exerciseRepository: ExerciseActivityRepositoryProtocol,
        goalsStore: GoalsStoring,
        diaryCalendar: DiaryCalendar = DiaryCalendar(),
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.foodRepository = foodRepository
        self.bodyRepository = bodyRepository
        self.dailyActivityRepository = dailyActivityRepository
        self.exerciseRepository = exerciseRepository
        self.goalsStore = goalsStore
        self.diaryCalendar = diaryCalendar
        self.nowProvider = nowProvider
    }

    var navigationTitle: String { "趋势与统计" }

    func selectRange(_ newRange: TrendRange) async {
        guard newRange != range else { return }
        range = newRange
        await load()
    }

    func selectNutrient(_ metric: TrendNutrientMetric) {
        selectedNutrient = metric
    }

    func selectActivityMetric(_ metric: TrendActivityMetric) {
        selectedActivityMetric = metric
    }

    func retry() async {
        await load()
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        // Keep prior snapshot visible during retry / range switch / pull-to-refresh.
        // Only the first load (no usable snapshot yet) uses a full-screen loading state.
        if currentSnapshot == nil {
            loadState = .loading
        }

        let endKey = diaryCalendar.dateKey(from: nowProvider())
        guard let bounds = TrendAggregator.startAndEndKeys(
            for: range,
            endingOn: endKey,
            calendar: diaryCalendar
        ) else {
            loadState = .error("无法计算日期范围。")
            return
        }

        async let foodResult = loadFoods(start: bounds.start, end: bounds.end)
        async let bodyResult = loadBody(start: bounds.start, end: bounds.end)
        async let dailyResult = loadDaily(start: bounds.start, end: bounds.end)
        async let exerciseResult = loadExercise(start: bounds.start, end: bounds.end)

        let foods = await foodResult
        let bodies = await bodyResult
        let dailies = await dailyResult
        let exercises = await exerciseResult

        guard generation == loadGeneration else { return }

        var failed: [String] = []
        var messages: [String] = []

        let foodItems: [FoodItem]
        switch foods {
        case .success(let value): foodItems = value
        case .failure(let message):
            foodItems = []
            failed.append("饮食")
            messages.append(message)
        }

        let bodyItems: [BodyMetric]
        switch bodies {
        case .success(let value): bodyItems = value
        case .failure(let message):
            bodyItems = []
            failed.append("身体")
            messages.append(message)
        }

        let activityItems: [DailyActivity]
        switch dailies {
        case .success(let value): activityItems = value
        case .failure(let message):
            activityItems = []
            failed.append("活动")
            messages.append(message)
        }

        let exerciseItems: [ExerciseActivity]
        switch exercises {
        case .success(let value): exerciseItems = value
        case .failure(let message):
            exerciseItems = []
            failed.append("运动")
            messages.append(message)
        }

        if failed.count == 4 {
            loadState = .error(messages.first ?? "无法加载趋势数据。")
            return
        }

        let goals = goalsStore.goals
        let snapshot = TrendAggregator.buildSnapshot(
            range: range,
            endDateKey: endKey,
            calendar: diaryCalendar,
            foods: foodItems,
            bodyMetrics: bodyItems,
            activities: activityItems,
            exercises: exerciseItems,
            goals: goals
        )

        if !failed.isEmpty {
            if snapshot.hasAnyData {
                loadState = .partial(
                    snapshot,
                    failedSources: failed,
                    message: "部分数据未能加载：\(failed.joined(separator: "、"))。"
                )
            } else {
                // Partial sources failed and nothing usable.
                loadState = .error(messages.first ?? "无法加载趋势数据。")
            }
            return
        }

        if snapshot.hasAnyData {
            loadState = .loaded(snapshot)
        } else {
            loadState = .empty(snapshot)
        }
    }

    // MARK: - Private loads

    /// Snapshot currently shown (if any), used to avoid blanking UI on retry.
    private var currentSnapshot: TrendSnapshot? {
        switch loadState {
        case .loaded(let snapshot), .empty(let snapshot):
            return snapshot
        case .partial(let snapshot, _, _):
            return snapshot
        case .loading, .error:
            return nil
        }
    }

    private enum SourceLoad<T: Sendable>: Sendable {
        case success(T)
        case failure(String)
    }

    private func loadFoods(start: String, end: String) async -> SourceLoad<[FoodItem]> {
        do {
            return .success(try await foodRepository.fetchBetween(startDateKey: start, endDateKey: end))
        } catch {
            return .failure(DataErrorMapping.map(error).userMessage)
        }
    }

    private func loadBody(start: String, end: String) async -> SourceLoad<[BodyMetric]> {
        do {
            return .success(try await bodyRepository.fetchBetween(startDateKey: start, endDateKey: end))
        } catch {
            return .failure(DataErrorMapping.map(error).userMessage)
        }
    }

    private func loadDaily(start: String, end: String) async -> SourceLoad<[DailyActivity]> {
        do {
            return .success(try await dailyActivityRepository.fetchBetween(startDateKey: start, endDateKey: end))
        } catch {
            return .failure(DataErrorMapping.map(error).userMessage)
        }
    }

    private func loadExercise(start: String, end: String) async -> SourceLoad<[ExerciseActivity]> {
        do {
            return .success(try await exerciseRepository.fetchBetween(startDateKey: start, endDateKey: end))
        } catch {
            return .failure(DataErrorMapping.map(error).userMessage)
        }
    }
}
