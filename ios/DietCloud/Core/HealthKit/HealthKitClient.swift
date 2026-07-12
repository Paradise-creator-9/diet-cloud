import Foundation
import HealthKit

/// Read-only HealthKit access. Never writes to the Health store.
protocol HealthKitClienting: Sendable {
    var isAvailable: Bool { get }
    func authorizationStatusSummary() -> HealthKitAuthStatus
    func requestReadAuthorization() async throws
    func fetchDay(dateKey: String, diaryCalendar: DiaryCalendar) async throws -> HealthKitDaySnapshot
}

final class HealthKitClient: HealthKitClienting, @unchecked Sendable {
    private let store: HKHealthStore?

    init() {
        if HKHealthStore.isHealthDataAvailable() {
            store = HKHealthStore()
        } else {
            store = nil
        }
    }

    var isAvailable: Bool {
        store != nil
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let distance = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) {
            types.insert(distance)
        }
        if let mass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(mass) }
        if let fat = HKObjectType.quantityType(forIdentifier: .bodyFatPercentage) { types.insert(fat) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func authorizationStatusSummary() -> HealthKitAuthStatus {
        guard let store else { return .unavailable }
        // Workout is representative; if any share status is sharingDenied we treat as denied.
        let workoutStatus = store.authorizationStatus(for: HKObjectType.workoutType())
        switch workoutStatus {
        case .notDetermined:
            return .notDetermined
        case .sharingDenied:
            return .denied
        case .sharingAuthorized:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }

    func requestReadAuthorization() async throws {
        guard let store else { throw HealthKitError.unavailable }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
        } catch {
            throw HealthKitError.authorizationFailed
        }
    }

    func fetchDay(dateKey: String, diaryCalendar: DiaryCalendar) async throws -> HealthKitDaySnapshot {
        guard let store else { throw HealthKitError.unavailable }
        guard let start = diaryCalendar.startOfDay(dateKey: dateKey),
              let end = diaryCalendar.endOfDayExclusive(dateKey: dateKey)
        else {
            throw HealthKitError.queryFailed
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let steps = cumulativeSum(
            store: store,
            identifier: .stepCount,
            unit: .count(),
            start: start,
            end: end
        )
        async let energy = cumulativeSum(
            store: store,
            identifier: .activeEnergyBurned,
            unit: .kilocalorie(),
            start: start,
            end: end
        )
        async let distanceMeters = cumulativeSum(
            store: store,
            identifier: .distanceWalkingRunning,
            unit: .meter(),
            start: start,
            end: end
        )
        async let weight = latestQuantity(
            store: store,
            identifier: .bodyMass,
            unit: .gramUnit(with: .kilo),
            predicate: predicate
        )
        async let bodyFat = latestQuantity(
            store: store,
            identifier: .bodyFatPercentage,
            unit: .percent(),
            predicate: predicate
        )
        async let workouts = fetchWorkouts(store: store, predicate: predicate)

        let stepsValue = try await steps
        let energyValue = try await energy
        let distanceValue = try await distanceMeters
        let weightValue = try await weight
        let fatValue = try await bodyFat
        let workoutSamples = try await workouts

        let snapshot = HealthKitDaySnapshot(
            dateKey: dateKey,
            steps: stepsValue,
            activeCalories: energyValue,
            distanceKm: distanceValue.map { $0 / 1000.0 },
            weightKg: weightValue,
            bodyFatPercent: fatValue.map { $0 * 100.0 },
            workouts: workoutSamples
        )
        if !snapshot.hasAnyData {
            throw HealthKitError.noData
        }
        return snapshot
    }

    // MARK: - Queries

    private func cumulativeSum(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if error != nil {
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private func latestQuantity(
        store: HKHealthStore,
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        predicate: NSPredicate
    ) async throws -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if error != nil {
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: sample.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }

    private func fetchWorkouts(store: HKHealthStore, predicate: NSPredicate) async throws -> [HealthKitWorkoutSample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if error != nil {
                    continuation.resume(throwing: HealthKitError.queryFailed)
                    return
                }
                let workouts = (samples as? [HKWorkout]) ?? []
                let mapped = workouts.map { workout -> HealthKitWorkoutSample in
                    let calories = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?
                        .sumQuantity()?
                        .doubleValue(for: .kilocalorie())
                        ?? workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
                        ?? 0
                    let meters = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
                    let minutes = workout.duration / 60.0
                    let typeName = Self.workoutTypeName(workout.workoutActivityType)
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime]
                    return HealthKitWorkoutSample(
                        externalId: workout.uuid.uuidString.lowercased(),
                        type: typeName,
                        title: typeName,
                        startedAt: formatter.string(from: workout.startDate),
                        durationMinutes: max(0, minutes),
                        activeCalories: max(0, calories),
                        distanceKm: max(0, meters / 1000.0)
                    )
                }
                continuation.resume(returning: mapped)
            }
            store.execute(query)
        }
    }

    private static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "跑步"
        case .walking: return "步行"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .hiking: return "徒步"
        case .yoga: return "瑜伽"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "力量训练"
        case .highIntensityIntervalTraining: return "HIIT"
        case .elliptical: return "椭圆机"
        case .rowing: return "划船"
        case .dance: return "舞蹈"
        case .cooldown: return "整理放松"
        case .other: return "其他"
        default: return "运动"
        }
    }
}

// MARK: - Mock

final class MockHealthKitClient: HealthKitClienting, @unchecked Sendable {
    var isAvailable: Bool = true
    var status: HealthKitAuthStatus = .authorized
    var snapshot: HealthKitDaySnapshot?
    var error: Error?
    private(set) var requestAuthCallCount = 0
    private(set) var lastFetchDateKey: String?

    func authorizationStatusSummary() -> HealthKitAuthStatus {
        isAvailable ? status : .unavailable
    }

    func requestReadAuthorization() async throws {
        requestAuthCallCount += 1
        if !isAvailable { throw HealthKitError.unavailable }
        if status == .denied { throw HealthKitError.authorizationDenied }
        status = .authorized
    }

    func fetchDay(dateKey: String, diaryCalendar: DiaryCalendar) async throws -> HealthKitDaySnapshot {
        lastFetchDateKey = dateKey
        if let error { throw error }
        if !isAvailable { throw HealthKitError.unavailable }
        if status == .denied { throw HealthKitError.authorizationDenied }
        guard var snap = snapshot else { throw HealthKitError.noData }
        snap.dateKey = dateKey
        if !snap.hasAnyData { throw HealthKitError.noData }
        return snap
    }
}
