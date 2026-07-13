import Foundation

/// One screenshot in the analyze-body request (matches Web payload shape).
struct BodyAnalysisScreenshotPayload: Equatable, Sendable, Encodable {
    let fileName: String
    let contentType: String
    /// `data:<mime>;base64,...` — never log this value.
    let dataUrl: String
}

/// Outbound request for `POST /api/analyze-body` (Web-compatible).
struct BodyAnalysisRequest: Equatable, Sendable, Encodable {
    let screenshot: BodyAnalysisScreenshotPayload

    /// Builds a request from compressed JPEG bytes only (no remote URLs).
    static func make(
        jpegData: Data,
        contentType: String = ImageCompressor.allowedContentType,
        fileName: String = "body-scale.jpg"
    ) throws -> BodyAnalysisRequest {
        guard !jpegData.isEmpty else {
            throw AppError.unknown(message: "请先选择身体数据截图。")
        }
        let dataUrl = MealAnalysisRequest.dataURL(for: jpegData, contentType: contentType)
        let request = BodyAnalysisRequest(
            screenshot: BodyAnalysisScreenshotPayload(
                fileName: fileName,
                contentType: contentType,
                dataUrl: dataUrl
            )
        )
        guard request.isLocalDataURL, !request.containsRemotePhotoURL else {
            throw AppError.unknown(message: "AI 分析不支持远程图片地址，请使用本地照片。")
        }
        return request
    }

    /// True when payload is a local `data:` URL (required for analyze-body).
    var isLocalDataURL: Bool {
        screenshot.dataUrl.lowercased().hasPrefix("data:")
    }

    /// True if the screenshot payload looks like a remote / file URL instead of a data URL.
    var containsRemotePhotoURL: Bool {
        let lower = screenshot.dataUrl.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("file:") {
            return true
        }
        // Absolute path or protocol-relative URL — not a local data URL.
        if lower.hasPrefix("//") || lower.hasPrefix("/") {
            return true
        }
        return false
    }
}

/// Domain result after decoding/normalizing `/api/analyze-body`.
/// Optional metrics use `nil` when the API returned null / missing (do not coerce to 0).
struct BodyAnalysisResult: Equatable, Sendable {
    var confidence: Double
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
    var notes: String
    var model: String?

    var isLowConfidence: Bool { confidence < 0.5 }
}

/// Applies AI metrics onto existing draft strings without wiping blanks for nulls.
enum BodyAnalysisFormFill {
    /// Format a finite metric for a TextField. Returns `nil` when value is unusable.
    static func formatMetric(_ value: Double?) -> String? {
        guard let value, value.isFinite else { return nil }
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    /// Overwrite `draft` only when `formatted` is non-nil (AI had a number).
    static func applyIfPresent(_ formatted: String?, onto draft: inout String) {
        guard let formatted else { return }
        draft = formatted
    }
}
