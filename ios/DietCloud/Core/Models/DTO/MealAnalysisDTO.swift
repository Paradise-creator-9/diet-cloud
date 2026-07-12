import Foundation

/// Wire response for `POST /api/analyze-meal`.
struct MealAnalysisAPIResponseDTO: Decodable, Equatable, Sendable {
    var ok: Bool?
    var model: String?
    var analysis: MealAnalysisDTO?
    var error: String?
    var code: String?
}

struct MealAnalysisDTO: Decodable, Equatable, Sendable {
    var dishName: String?
    var confidence: Double?
    var total: MealAnalysisNutritionDTO?
    var items: [MealAnalysisItemDTO]?
    var notes: String?
}

struct MealAnalysisNutritionDTO: Decodable, Equatable, Sendable {
    var grams: Double?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
}

struct MealAnalysisItemDTO: Decodable, Equatable, Sendable {
    var name: String?
    var grams: Double?
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var reasoning: String?
}

enum MealAnalysisDTOMapper {
    static func domain(from dto: MealAnalysisAPIResponseDTO) throws -> MealAnalysisResult {
        guard let analysis = dto.analysis else {
            throw AppError.unknown(message: "AI 返回格式无效。")
        }
        return domain(from: analysis, model: dto.model)
    }

    static func domain(from analysis: MealAnalysisDTO, model: String?) -> MealAnalysisResult {
        let itemsDTO = analysis.items ?? []
        let items: [MealAnalysisItem] = itemsDTO.map { item in
            MealAnalysisItem(
                name: nonEmpty(item.name, fallback: "未知食物"),
                grams: number(item.grams),
                calories: number(item.calories),
                protein: number(item.protein),
                carbs: number(item.carbs),
                fat: number(item.fat),
                fiber: number(item.fiber),
                reasoning: item.reasoning ?? ""
            )
        }

        let totalDTO = analysis.total
        var total = MealAnalysisNutrition(
            grams: number(totalDTO?.grams),
            calories: number(totalDTO?.calories),
            protein: number(totalDTO?.protein),
            carbs: number(totalDTO?.carbs),
            fat: number(totalDTO?.fat),
            fiber: number(totalDTO?.fiber)
        )

        // If total is empty but items exist, sum items (defensive; API usually sends total).
        if total.calories == 0, !items.isEmpty {
            total = MealAnalysisNutrition(
                grams: items.reduce(0) { $0 + $1.grams },
                calories: items.reduce(0) { $0 + $1.calories },
                protein: items.reduce(0) { $0 + $1.protein },
                carbs: items.reduce(0) { $0 + $1.carbs },
                fat: items.reduce(0) { $0 + $1.fat },
                fiber: items.reduce(0) { $0 + $1.fiber }
            )
        }

        let dishFromItems = items.map(\.name).filter { !$0.isEmpty }.prefix(3).joined(separator: "、")
        let dishName = nonEmpty(analysis.dishName, fallback: dishFromItems.isEmpty ? "AI 识别餐食" : dishFromItems)
        let confidence = min(1, max(0, analysis.confidence ?? 0.6))
        let notes = analysis.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? (analysis.notes ?? "")
            : "AI 估算结果，仅供饮食记录参考。"

        return MealAnalysisResult(
            dishName: dishName,
            confidence: confidence,
            total: total,
            items: items,
            notes: notes,
            model: model
        )
    }

    private static func number(_ value: Double?) -> Double {
        guard let value, value.isFinite else { return 0 }
        return value
    }

    private static func nonEmpty(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }
}
