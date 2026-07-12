import XCTest
@testable import DietCloud

final class TrendAggregatorTests: XCTestCase {
    private let calendar = DiaryCalendar.tokyo()
    /// Fixed end day for deterministic windows.
    private let endKey = "2026-07-13"

    func testSevenDayWindowIncludesTodayAndSixPrior() {
        let keys = TrendAggregator.dateKeys(for: .days7, endingOn: endKey, calendar: calendar)
        XCTAssertEqual(keys.count, 7)
        XCTAssertEqual(keys.first, "2026-07-07")
        XCTAssertEqual(keys.last, "2026-07-13")
        XCTAssertEqual(keys, [
            "2026-07-07", "2026-07-08", "2026-07-09", "2026-07-10",
            "2026-07-11", "2026-07-12", "2026-07-13"
        ])
    }

    func testThirtyDayWindowCountAndInclusiveEnds() {
        let keys = TrendAggregator.dateKeys(for: .days30, endingOn: endKey, calendar: calendar)
        XCTAssertEqual(keys.count, 30)
        XCTAssertEqual(keys.last, endKey)
        XCTAssertEqual(keys.first, "2026-06-14")
        let bounds = TrendAggregator.startAndEndKeys(for: .days30, endingOn: endKey, calendar: calendar)
        XCTAssertEqual(bounds?.start, keys.first)
        XCTAssertEqual(bounds?.end, keys.last)
    }

    func testNutritionAggregatesPerDayWithoutCrossDayLeak() {
        let foods = [
            makeFood(id: "a", date: "2026-07-12", cal: 100, protein: 10, carbs: 20, fiber: 2),
            makeFood(id: "b", date: "2026-07-12", cal: 50, protein: 5, carbs: 10, fiber: 1),
            makeFood(id: "c", date: "2026-07-13", cal: 200, protein: 20, carbs: 30, fiber: 5)
        ]
        let byDay = TrendAggregator.nutritionByDay(from: foods)
        XCTAssertEqual(byDay["2026-07-12"]?.calories, 150)
        XCTAssertEqual(byDay["2026-07-12"]?.protein, 15)
        XCTAssertEqual(byDay["2026-07-12"]?.fiber, 3)
        XCTAssertEqual(byDay["2026-07-13"]?.calories, 200)
        XCTAssertEqual(byDay.count, 2)
    }

    func testMissingDaysDoNotCreateSyntheticNutritionOrWeightPoints() {
        let foods = [makeFood(id: "a", date: "2026-07-13", cal: 500, protein: 30, carbs: 40, fiber: 8)]
        let bodies = [makeBody(id: "w1", date: "2026-07-11", weight: 70, created: "2026-07-11T10:00:00Z")]
        let snap = TrendAggregator.buildSnapshot(
            range: .days7,
            endDateKey: endKey,
            calendar: calendar,
            foods: foods,
            bodyMetrics: bodies,
            activities: [],
            exercises: [],
            goals: .empty
        )
        XCTAssertEqual(snap.nutritionByDay.count, 1)
        XCTAssertNil(snap.nutritionByDay["2026-07-12"])
        XCTAssertEqual(snap.intakePoints().map(\.dateKey), ["2026-07-13"])
        XCTAssertEqual(snap.weightPoints().map(\.dateKey), ["2026-07-11"])
        // No zero fake for missing days
        XCTAssertFalse(snap.intakePoints().contains { $0.value == 0 && $0.dateKey == "2026-07-12" })
    }

    func testAverageDenominatorUsesOnlyFoodDays() {
        let foods = [
            makeFood(id: "a", date: "2026-07-12", cal: 100, protein: 0, carbs: 0, fiber: 0),
            makeFood(id: "b", date: "2026-07-13", cal: 300, protein: 0, carbs: 0, fiber: 0)
        ]
        let snap = TrendAggregator.buildSnapshot(
            range: .days7,
            endDateKey: endKey,
            calendar: calendar,
            foods: foods,
            bodyMetrics: [],
            activities: [],
            exercises: [],
            goals: .empty
        )
        XCTAssertEqual(snap.summary.foodRecordedDays, 2)
        XCTAssertEqual(snap.summary.averageIntakeKcal ?? -1, 200, accuracy: 0.0001)
    }

    func testHealthKitActivityPreferredOverManual() {
        let manual = makeDaily(id: "m", date: "2026-07-13", source: "manual", steps: 1000, active: 100, created: "2026-07-13T20:00:00Z")
        let hk = makeDaily(id: "h", date: "2026-07-13", source: "healthkit", steps: 8000, active: 400, created: "2026-07-13T08:00:00Z")
        let picked = TrendAggregator.activityByDay(from: [manual, hk])
        XCTAssertEqual(picked["2026-07-13"]?.id, "h")
        XCTAssertEqual(picked["2026-07-13"]?.steps, 8000)
    }

    func testExerciseSameDaySumsSessionsDurationAndCalories() {
        let exercises = [
            makeExercise(id: "e1", date: "2026-07-13", duration: 20, cal: 100),
            makeExercise(id: "e2", date: "2026-07-13", duration: 40, cal: 200)
        ]
        let byDay = TrendAggregator.exerciseByDay(from: exercises)
        XCTAssertEqual(byDay["2026-07-13"]?.sessionCount, 2)
        XCTAssertEqual(byDay["2026-07-13"]?.durationMinutes, 60)
        XCTAssertEqual(byDay["2026-07-13"]?.activeCalories, 300)

        let snap = TrendAggregator.buildSnapshot(
            range: .days7,
            endDateKey: endKey,
            calendar: calendar,
            foods: [],
            bodyMetrics: [],
            activities: [],
            exercises: exercises,
            goals: .empty
        )
        XCTAssertEqual(snap.summary.exerciseSessionCount, 2)
        XCTAssertEqual(snap.summary.exerciseTotalMinutes, 60)
    }

    func testWeightPicksLatestCreatedAtPerDay() {
        let older = makeBody(id: "a", date: "2026-07-13", weight: 71, created: "2026-07-13T08:00:00Z")
        let newer = makeBody(id: "b", date: "2026-07-13", weight: 70.2, created: "2026-07-13T18:00:00Z")
        let byDay = TrendAggregator.weightByDay(from: [older, newer])
        XCTAssertEqual(byDay["2026-07-13"] ?? -1, 70.2, accuracy: 0.0001)
    }

    func testCalorieBandBoundaries90And110Percent() {
        XCTAssertTrue(TrendAggregator.isCalorieInBand(intake: 1800, goal: 2000)) // 90%
        XCTAssertTrue(TrendAggregator.isCalorieInBand(intake: 2200, goal: 2000)) // 110%
        XCTAssertTrue(TrendAggregator.isCalorieInBand(intake: 2000, goal: 2000))
        XCTAssertFalse(TrendAggregator.isCalorieInBand(intake: 1799, goal: 2000))
        XCTAssertFalse(TrendAggregator.isCalorieInBand(intake: 2201, goal: 2000))
    }

    func testProteinAndFiberGoalMetAndComposite() {
        let foods = [
            makeFood(id: "ok", date: "2026-07-12", cal: 2000, protein: 120, carbs: 200, fiber: 30),
            makeFood(id: "lowP", date: "2026-07-13", cal: 2000, protein: 50, carbs: 200, fiber: 30)
        ]
        let goals = UserGoals(
            dailyCaloriesKcal: 2000,
            targetWeightKg: nil,
            proteinGrams: 100,
            carbsGrams: 250, // carbs must not affect composite
            fiberGrams: 25,
            fatGrams: nil
        )
        let nutrition = TrendAggregator.nutritionByDay(from: foods)
        let status = TrendAggregator.goalMetStatus(nutritionByDay: nutrition, goals: goals)
        guard case .configured(let met) = status else {
            return XCTFail("expected configured")
        }
        // only 2026-07-12 meets protein ≥ 100
        XCTAssertEqual(met, 1)
    }

    func testNoGoalsShowsNotConfigured() {
        let foods = [makeFood(id: "a", date: "2026-07-13", cal: 500, protein: 10, carbs: 10, fiber: 2)]
        let status = TrendAggregator.goalMetStatus(
            nutritionByDay: TrendAggregator.nutritionByDay(from: foods),
            goals: .empty
        )
        XCTAssertEqual(status, .notConfigured)
    }

    func testCarbsOnlyGoalDoesNotConfigureComposite() {
        // Only carbs set among macros — composite ignores carbs; calorie/protein/fiber unset.
        let goals = UserGoals(
            dailyCaloriesKcal: nil,
            targetWeightKg: nil,
            proteinGrams: nil,
            carbsGrams: 200,
            fiberGrams: nil,
            fatGrams: nil
        )
        let foods = [makeFood(id: "a", date: "2026-07-13", cal: 500, protein: 10, carbs: 250, fiber: 2)]
        let status = TrendAggregator.goalMetStatus(
            nutritionByDay: TrendAggregator.nutritionByDay(from: foods),
            goals: goals
        )
        XCTAssertEqual(status, .notConfigured)
    }

    // MARK: - Fixtures

    private func makeFood(
        id: String,
        date: String,
        cal: Double,
        protein: Double,
        carbs: Double,
        fiber: Double
    ) -> FoodItem {
        FoodItem(
            id: id,
            dateKey: date,
            meal: .lunch,
            name: id,
            grams: 0,
            calories: cal,
            protein: protein,
            carbs: carbs,
            fat: 0,
            fiber: fiber,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "\(date)T12:00:00Z",
            sourceId: nil
        )
    }

    private func makeBody(id: String, date: String, weight: Double, created: String) -> BodyMetric {
        BodyMetric(
            id: id,
            dateKey: date,
            measuredAt: "\(date)T12:00:00",
            score: 0,
            weightKg: weight,
            bmi: 0,
            bodyFatPercent: 0,
            bodyAge: 0,
            bodyType: "",
            muscleKg: 0,
            skeletalMuscleKg: 0,
            boneMassKg: 0,
            waterPercent: 0,
            visceralFat: 0,
            bmrKcal: 0,
            proteinPercent: 0,
            trunkFatPercent: 0,
            trunkMuscleKg: 0,
            leftArmFatPercent: 0,
            leftArmMuscleKg: 0,
            rightArmFatPercent: 0,
            rightArmMuscleKg: 0,
            leftLegFatPercent: 0,
            leftLegMuscleKg: 0,
            rightLegFatPercent: 0,
            rightLegMuscleKg: 0,
            note: "",
            createdAt: created
        )
    }

    private func makeDaily(
        id: String,
        date: String,
        source: String,
        steps: Double,
        active: Double,
        created: String
    ) -> DailyActivity {
        DailyActivity(
            id: id,
            dateKey: date,
            source: source,
            steps: steps,
            activeCalories: active,
            totalCalories: active,
            exerciseMinutes: 0,
            standHours: 0,
            distanceKm: 0,
            floors: 0,
            restingHeartRate: 0,
            hrvMs: 0,
            sleepMinutes: 0,
            rawMetrics: [:],
            note: "",
            createdAt: created
        )
    }

    private func makeExercise(id: String, date: String, duration: Double, cal: Double) -> ExerciseActivity {
        ExerciseActivity(
            id: id,
            dateKey: date,
            startedAt: "\(date)T12:00:00",
            source: "manual",
            externalId: "",
            type: "骑行",
            title: id,
            durationMinutes: duration,
            distanceKm: 0,
            activeCalories: cal,
            avgHeartRate: 0,
            maxHeartRate: 0,
            elevationGainM: 0,
            note: "",
            createdAt: "\(date)T12:00:00Z"
        )
    }
}

final class MockRepositoryRangeTests: XCTestCase {
    private let userId = "11111111-1111-1111-1111-111111111111"

    func testFoodFetchBetweenIsInclusiveOnBoundaries() async throws {
        let repo = MockFoodItemRepository(sessionUserId: userId, seed: [
            makeFood("out-before", "2026-07-06"),
            makeFood("start", "2026-07-07"),
            makeFood("mid", "2026-07-10"),
            makeFood("end", "2026-07-13"),
            makeFood("out-after", "2026-07-14")
        ])
        let rows = try await repo.fetchBetween(startDateKey: "2026-07-07", endDateKey: "2026-07-13")
        XCTAssertEqual(rows.map(\.dateKey), ["2026-07-07", "2026-07-10", "2026-07-13"])
        XCTAssertEqual(repo.lastFetchBetween?.0, "2026-07-07")
        XCTAssertEqual(repo.lastFetchBetween?.1, "2026-07-13")
    }

    private func makeFood(_ id: String, _ date: String) -> FoodItem {
        FoodItem(
            id: id,
            dateKey: date,
            meal: .snack,
            name: id,
            grams: 0,
            calories: 10,
            protein: 0,
            carbs: 0,
            fat: 0,
            fiber: 0,
            note: "",
            photoPaths: [],
            photoURLs: [],
            createdAt: "\(date)T01:00:00Z",
            sourceId: nil
        )
    }
}
