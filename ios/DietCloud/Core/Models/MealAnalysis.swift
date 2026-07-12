import Foundation

/// One photo in the analyze-meal request (matches Web payload shape).
struct MealAnalysisPhotoPayload: Equatable, Sendable, Encodable {
    let fileName: String
    let contentType: String
    /// `data:<mime>;base64,...` — never log this value.
    let dataUrl: String
}

/// Outbound request for `POST /api/analyze-meal` (Web-compatible).
struct MealAnalysisRequest: Equatable, Sendable, Encodable {
    let photos: [MealAnalysisPhotoPayload]
    let hint: String

    enum CodingKeys: String, CodingKey {
        case photos
        case hint
    }

    /// Builds a request from optional hint text and optional compressed JPEG bytes.
    /// - Note: Does not accept signed URLs or remote photo paths.
    static func make(
        hint: String,
        jpegData: Data?,
        contentType: String = ImageCompressor.allowedContentType,
        fileName: String = "meal.jpg"
    ) throws -> MealAnalysisRequest {
        let trimmed = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        var photos: [MealAnalysisPhotoPayload] = []
        if let jpegData, !jpegData.isEmpty {
            let dataUrl = Self.dataURL(for: jpegData, contentType: contentType)
            photos.append(
                MealAnalysisPhotoPayload(
                    fileName: fileName,
                    contentType: contentType,
                    dataUrl: dataUrl
                )
            )
        }
        guard !photos.isEmpty || !trimmed.isEmpty else {
            throw AppError.unknown(message: "请先选择照片，或者至少写一句文字说明。")
        }
        return MealAnalysisRequest(photos: photos, hint: trimmed)
    }

    static func dataURL(for data: Data, contentType: String) -> String {
        "data:\(contentType);base64,\(data.base64EncodedString())"
    }

    /// True if any photo payload looks like an http(s) URL instead of a data URL.
    var containsRemotePhotoURL: Bool {
        photos.contains { payload in
            let lower = payload.dataUrl.lowercased()
            return lower.hasPrefix("http://") || lower.hasPrefix("https://")
        }
    }
}

struct MealAnalysisNutrition: Equatable, Sendable {
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double

    static let zero = MealAnalysisNutrition(
        grams: 0, calories: 0, protein: 0, carbs: 0, fat: 0, fiber: 0
    )
}

struct MealAnalysisItem: Equatable, Sendable, Identifiable {
    var id: String { name + "-\(calories)" }
    var name: String
    var grams: Double
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double
    var reasoning: String
}

/// Domain result after decoding/normalizing `/api/analyze-meal`.
struct MealAnalysisResult: Equatable, Sendable {
    var dishName: String
    var confidence: Double
    var total: MealAnalysisNutrition
    var items: [MealAnalysisItem]
    var notes: String
    var model: String?
}

/// Values applied to the add-food form (user still confirms before save).
struct MealAnalysisFormFill: Equatable, Sendable {
    var name: String
    var calories: String
    var protein: String
    var carbs: String
    var fat: String
    var grams: String
    var fiber: Double
    var note: String
    var summary: String
}

enum MealAnalysisMapper {
    /// Maps API analysis into form fields. Does not auto-save.
    static func formFill(from result: MealAnalysisResult, userHint: String) -> MealAnalysisFormFill {
        let total = result.total
        let confPct = Int((result.confidence * 100).rounded())
        let itemCount = max(1, result.items.count)
        let modeLabel: String
        if userHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modeLabel = "AI 照片估算"
        } else if result.items.isEmpty {
            modeLabel = "AI 估算"
        } else {
            modeLabel = "AI 估算"
        }

        var noteParts: [String] = []
        let hint = userHint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !hint.isEmpty {
            noteParts.append("用户补充：\(hint)")
        }
        noteParts.append("\(modeLabel)，置信度约 \(confPct)%。")
        let notes = result.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            noteParts.append(notes)
        }

        let name = result.dishName.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = name.isEmpty ? "AI 识别餐食" : name

        return MealAnalysisFormFill(
            name: displayName,
            calories: formatNumber(total.calories),
            protein: formatNumber(total.protein),
            carbs: formatNumber(total.carbs),
            fat: formatNumber(total.fat),
            grams: formatNumber(total.grams),
            fiber: total.fiber,
            note: noteParts.joined(separator: "\n"),
            summary: "已识别 \(itemCount) 个食物，约 \(formatNumber(total.calories)) kcal。请确认后保存。"
        )
    }

    private static func formatNumber(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}
