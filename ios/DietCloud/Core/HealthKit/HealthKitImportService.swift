import Foundation

/// Applies a HealthKit day snapshot into body / daily / exercise repositories.
/// Never writes to HealthKit. Does not touch food items.
protocol HealthKitImportServicing: Sendable {
    func importDay(
        dateKey: String,
        snapshot: HealthKitDaySnapshot,
        existingBody: BodyMetric?,
        existingDaily: DailyActivity?,
        existingExercises: [ExerciseActivity],
        overwriteManual: Bool
    ) async throws -> HealthKitImportResult
}

struct HealthKitImportService: HealthKitImportServicing {
    private let bodyRepository: BodyMetricsRepositoryProtocol
    private let dailyRepository: DailyActivityRepositoryProtocol
    private let exerciseRepository: ExerciseActivityRepositoryProtocol

    init(
        bodyRepository: BodyMetricsRepositoryProtocol,
        dailyRepository: DailyActivityRepositoryProtocol,
        exerciseRepository: ExerciseActivityRepositoryProtocol
    ) {
        self.bodyRepository = bodyRepository
        self.dailyRepository = dailyRepository
        self.exerciseRepository = exerciseRepository
    }

    func importDay(
        dateKey: String,
        snapshot: HealthKitDaySnapshot,
        existingBody: BodyMetric?,
        existingDaily: DailyActivity?,
        existingExercises: [ExerciseActivity],
        overwriteManual: Bool
    ) async throws -> HealthKitImportResult {
        var importedDaily = false
        var importedBody = false
        var importedWorkouts = 0
        var skippedWorkouts = 0
        var skippedDailyBecauseManual = false
        var skippedBodyBecauseManual = false
        var notes: [String] = []

        // MARK: Daily activity (source = healthkit)
        if snapshot.hasDailyActivityData {
            let manualDaily = existingDaily.flatMap { $0.source == "manual" ? $0 : nil }
            if let manualDaily, !overwriteManual {
                skippedDailyBecauseManual = true
                notes.append("已有手动每日活动，未覆盖（可确认后用健康数据更新）。")
                _ = manualDaily
            } else {
                if overwriteManual, let manual = manualDaily {
                    try await dailyRepository.delete(id: manual.id)
                }
                let write = DailyActivityWrite(
                    dateKey: dateKey,
                    source: "healthkit",
                    steps: snapshot.steps ?? 0,
                    activeCalories: snapshot.activeCalories ?? 0,
                    totalCalories: snapshot.activeCalories ?? 0,
                    exerciseMinutes: 0,
                    standHours: 0,
                    distanceKm: snapshot.distanceKm ?? 0,
                    floors: 0,
                    restingHeartRate: 0,
                    hrvMs: 0,
                    sleepMinutes: 0,
                    rawMetrics: [:],
                    note: "来自 Apple 健康"
                )
                _ = try await dailyRepository.upsert(write)
                importedDaily = true
            }
        }

        // MARK: Body (no source column — confirm before overwrite)
        if snapshot.hasBodyData {
            let hasExistingBody = (existingBody?.weightKg ?? 0) > 0
                || (existingBody?.bodyFatPercent ?? 0) > 0
            if hasExistingBody, !overwriteManual {
                skippedBodyBecauseManual = true
                notes.append("已有身体数据，未覆盖（可确认后用健康数据更新）。")
            } else {
                let weight = snapshot.weightKg ?? existingBody?.weightKg ?? 0
                let fat = snapshot.bodyFatPercent ?? existingBody?.bodyFatPercent ?? 0
                if weight > 0 || fat > 0 {
                    let write = BodyMetricWrite.manual(
                        dateKey: dateKey,
                        weightKg: weight,
                        bodyFatPercent: fat,
                        note: "来自 Apple 健康",
                        existing: existingBody
                    )
                    _ = try await bodyRepository.upsert(write)
                    importedBody = true
                }
            }
        }

        // MARK: Workouts (dedupe by source+external_id)
        let existingHKIds = Set(
            existingExercises
                .filter { $0.source == "healthkit" }
                .map(\.externalId)
                .filter { !$0.isEmpty }
        )
        // Best-effort fallback fingerprint for rows without external id
        let existingFingerprints = Set(
            existingExercises.map { Self.fingerprint(type: $0.type, startedAt: $0.startedAt, duration: $0.durationMinutes, calories: $0.activeCalories) }
        )

        for workout in snapshot.workouts {
            if existingHKIds.contains(workout.externalId) {
                skippedWorkouts += 1
                continue
            }
            let fp = Self.fingerprint(
                type: workout.type,
                startedAt: workout.startedAt,
                duration: workout.durationMinutes,
                calories: workout.activeCalories
            )
            if existingFingerprints.contains(fp) {
                skippedWorkouts += 1
                continue
            }
            let write = ExerciseActivityWrite(
                dateKey: dateKey,
                startedAt: workout.startedAt,
                source: "healthkit",
                externalId: workout.externalId,
                type: workout.type,
                title: workout.title,
                durationMinutes: workout.durationMinutes,
                distanceKm: workout.distanceKm,
                activeCalories: workout.activeCalories,
                avgHeartRate: 0,
                maxHeartRate: 0,
                elevationGainM: 0,
                note: "来自 Apple 健康"
            )
            _ = try await exerciseRepository.create(write)
            importedWorkouts += 1
        }

        if !importedDaily, !importedBody, importedWorkouts == 0, skippedWorkouts == 0,
           skippedDailyBecauseManual || skippedBodyBecauseManual {
            return HealthKitImportResult(
                importedDaily: false,
                importedBody: false,
                importedWorkouts: 0,
                skippedWorkouts: 0,
                skippedDailyBecauseManual: skippedDailyBecauseManual,
                skippedBodyBecauseManual: skippedBodyBecauseManual,
                userMessage: notes.joined(separator: " ")
            )
        }

        var summaryParts: [String] = []
        if importedDaily { summaryParts.append("每日活动") }
        if importedBody { summaryParts.append("身体数据") }
        if importedWorkouts > 0 { summaryParts.append("运动 \(importedWorkouts) 条") }
        if skippedWorkouts > 0 { summaryParts.append("跳过重复运动 \(skippedWorkouts) 条") }
        summaryParts.append(contentsOf: notes)

        let userMessage: String
        if summaryParts.isEmpty {
            userMessage = "健康数据已检查，没有可写入的新记录。"
        } else if importedDaily || importedBody || importedWorkouts > 0 {
            userMessage = "已导入：" + summaryParts.joined(separator: "；")
        } else {
            userMessage = summaryParts.joined(separator: " ")
        }

        return HealthKitImportResult(
            importedDaily: importedDaily,
            importedBody: importedBody,
            importedWorkouts: importedWorkouts,
            skippedWorkouts: skippedWorkouts,
            skippedDailyBecauseManual: skippedDailyBecauseManual,
            skippedBodyBecauseManual: skippedBodyBecauseManual,
            userMessage: userMessage
        )
    }

    static func fingerprint(type: String, startedAt: String, duration: Double, calories: Double) -> String {
        let d = Int(duration.rounded())
        let c = Int(calories.rounded())
        return "\(type)|\(startedAt)|\(d)|\(c)"
    }

    /// True when existing app data would be overwritten by HealthKit body/daily import.
    static func needsOverwriteConfirmation(
        snapshot: HealthKitDaySnapshot,
        existingBody: BodyMetric?,
        existingDaily: DailyActivity?
    ) -> Bool {
        let manualDaily = existingDaily?.source == "manual"
            && ((existingDaily?.steps ?? 0) > 0
                || (existingDaily?.activeCalories ?? 0) > 0
                || (existingDaily?.distanceKm ?? 0) > 0)
        let bodyConflict = snapshot.hasBodyData
            && ((existingBody?.weightKg ?? 0) > 0 || (existingBody?.bodyFatPercent ?? 0) > 0)
        let dailyConflict = snapshot.hasDailyActivityData && manualDaily
        return bodyConflict || dailyConflict
    }
}
