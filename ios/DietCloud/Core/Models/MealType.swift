import Foundation

/// Matches Postgres `public.meal_type` and Web `MealType`.
enum MealType: String, Codable, CaseIterable, Sendable, Equatable {
    case breakfast
    case lunch
    case dinner
    case snack

    var titleZh: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .dinner: return "晚餐"
        case .snack: return "加餐"
        }
    }

    /// Fixed Web display order.
    static let displayOrder: [MealType] = [.breakfast, .lunch, .dinner, .snack]
}
