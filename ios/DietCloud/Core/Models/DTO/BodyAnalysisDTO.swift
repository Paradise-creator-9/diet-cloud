import Foundation

/// Wire response for `POST /api/analyze-body`.
struct BodyAnalysisAPIResponseDTO: Decodable, Equatable, Sendable {
    var ok: Bool?
    var model: String?
    var analysis: BodyAnalysisDTO?
    var error: String?
    var code: String?
}

/// Mirrors server `normalizeAnalysis` field names (camelCase JSON).
struct BodyAnalysisDTO: Decodable, Equatable, Sendable {
    var confidence: Double?
    var date: String?
    var measuredAt: String?
    var score: Double?
    var weightKg: Double?
    var bmi: Double?
    var bodyFatPercent: Double?
    var bodyAge: Double?
    var bodyType: String?
    var muscleKg: Double?
    var skeletalMuscleKg: Double?
    var boneMassKg: Double?
    var waterPercent: Double?
    var visceralFat: Double?
    var bmrKcal: Double?
    var proteinPercent: Double?
    var trunkFatPercent: Double?
    var trunkMuscleKg: Double?
    var leftArmFatPercent: Double?
    var leftArmMuscleKg: Double?
    var rightArmFatPercent: Double?
    var rightArmMuscleKg: Double?
    var leftLegFatPercent: Double?
    var leftLegMuscleKg: Double?
    var rightLegFatPercent: Double?
    var rightLegMuscleKg: Double?
    var notes: String?
}

enum BodyAnalysisDTOMapper {
    static func domain(from dto: BodyAnalysisAPIResponseDTO) throws -> BodyAnalysisResult {
        guard let analysis = dto.analysis else {
            throw AppError.unknown(message: "AI 返回格式无效。")
        }
        return domain(from: analysis, model: dto.model)
    }

    static func domain(from analysis: BodyAnalysisDTO, model: String?) -> BodyAnalysisResult {
        BodyAnalysisResult(
            confidence: clamp01(analysis.confidence ?? 0.65),
            date: nonEmpty(analysis.date),
            measuredAt: nonEmpty(analysis.measuredAt),
            score: finite(analysis.score),
            weightKg: finite(analysis.weightKg),
            bmi: finite(analysis.bmi),
            bodyFatPercent: finite(analysis.bodyFatPercent),
            bodyAge: finite(analysis.bodyAge),
            bodyType: nonEmpty(analysis.bodyType),
            muscleKg: finite(analysis.muscleKg),
            skeletalMuscleKg: finite(analysis.skeletalMuscleKg),
            boneMassKg: finite(analysis.boneMassKg),
            waterPercent: finite(analysis.waterPercent),
            visceralFat: finite(analysis.visceralFat),
            bmrKcal: finite(analysis.bmrKcal),
            proteinPercent: finite(analysis.proteinPercent),
            trunkFatPercent: finite(analysis.trunkFatPercent),
            trunkMuscleKg: finite(analysis.trunkMuscleKg),
            leftArmFatPercent: finite(analysis.leftArmFatPercent),
            leftArmMuscleKg: finite(analysis.leftArmMuscleKg),
            rightArmFatPercent: finite(analysis.rightArmFatPercent),
            rightArmMuscleKg: finite(analysis.rightArmMuscleKg),
            leftLegFatPercent: finite(analysis.leftLegFatPercent),
            leftLegMuscleKg: finite(analysis.leftLegMuscleKg),
            rightLegFatPercent: finite(analysis.rightLegFatPercent),
            rightLegMuscleKg: finite(analysis.rightLegMuscleKg),
            notes: nonEmpty(analysis.notes) ?? "体脂秤截图 OCR 识别结果，请保存前检查。",
            model: model
        )
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0.65 }
        return min(1, max(0, value))
    }
}
