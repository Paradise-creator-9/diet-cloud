import Foundation

/// Five local daily reminders (Stage 12).
enum ReminderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast
    case lunch
    case dinner
    case weighIn
    case dailySummary

    var id: String { rawValue }

    /// Stable UNNotificationRequest identifier.
    var notificationIdentifier: String {
        switch self {
        case .breakfast: return "dietcloud.reminder.breakfast"
        case .lunch: return "dietcloud.reminder.lunch"
        case .dinner: return "dietcloud.reminder.dinner"
        case .weighIn: return "dietcloud.reminder.weighIn"
        case .dailySummary: return "dietcloud.reminder.dailySummary"
        }
    }

    var title: String {
        switch self {
        case .breakfast: return "早餐记录提醒"
        case .lunch: return "午餐记录提醒"
        case .dinner: return "晚餐记录提醒"
        case .weighIn: return "每日称重提醒"
        case .dailySummary: return "每日总结提醒"
        }
    }

    var notificationTitle: String {
        switch self {
        case .breakfast: return "记录早餐"
        case .lunch: return "记录午餐"
        case .dinner: return "记录晚餐"
        case .weighIn: return "每日称重"
        case .dailySummary: return "今日饮食总结"
        }
    }

    var notificationBody: String {
        switch self {
        case .breakfast: return "记得补充今天的早餐记录。"
        case .lunch: return "别忘了记录今天的午餐。"
        case .dinner: return "记得补充今天的晚餐记录。"
        case .weighIn: return "可以记录一下今天的身体数据。"
        case .dailySummary: return "回顾一下今天的饮食和活动记录。"
        }
    }

    static var allStableIdentifiers: [String] {
        allCases.map(\.notificationIdentifier)
    }
}

/// Local clock time (hour/minute) for calendar triggers.
struct ReminderTime: Equatable, Codable, Sendable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    /// Binding helper for `DatePicker`.
    func date(on calendar: Calendar = .current, reference: Date = Date()) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day], from: reference)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0
        return calendar.date(from: comps) ?? reference
    }

    static func from(date: Date, calendar: Calendar = .current) -> ReminderTime {
        let comps = calendar.dateComponents([.hour, .minute], from: date)
        return ReminderTime(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
    }
}

struct ReminderItem: Equatable, Codable, Sendable {
    var isEnabled: Bool
    var time: ReminderTime
}

/// Full local reminder configuration. Not stored in Supabase.
struct ReminderSettings: Equatable, Codable, Sendable {
    var breakfast: ReminderItem
    var lunch: ReminderItem
    var dinner: ReminderItem
    var weighIn: ReminderItem
    var dailySummary: ReminderItem

    static let `default` = ReminderSettings(
        breakfast: ReminderItem(isEnabled: false, time: ReminderTime(hour: 8, minute: 0)),
        lunch: ReminderItem(isEnabled: false, time: ReminderTime(hour: 12, minute: 30)),
        dinner: ReminderItem(isEnabled: false, time: ReminderTime(hour: 19, minute: 0)),
        weighIn: ReminderItem(isEnabled: false, time: ReminderTime(hour: 7, minute: 30)),
        dailySummary: ReminderItem(isEnabled: false, time: ReminderTime(hour: 21, minute: 30))
    )

    subscript(kind: ReminderKind) -> ReminderItem {
        get {
            switch kind {
            case .breakfast: return breakfast
            case .lunch: return lunch
            case .dinner: return dinner
            case .weighIn: return weighIn
            case .dailySummary: return dailySummary
            }
        }
        set {
            switch kind {
            case .breakfast: breakfast = newValue
            case .lunch: lunch = newValue
            case .dinner: dinner = newValue
            case .weighIn: weighIn = newValue
            case .dailySummary: dailySummary = newValue
            }
        }
    }

    var anyEnabled: Bool {
        ReminderKind.allCases.contains { self[$0].isEnabled }
    }

    var enabledKinds: [ReminderKind] {
        ReminderKind.allCases.filter { self[$0].isEnabled }
    }
}

/// Domain mapping of `UNAuthorizationStatus`.
enum NotificationAuthStatus: String, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    /// Includes ephemeral / unknown — not treated as schedulable.
    case unsupported

    var canSchedule: Bool {
        switch self {
        case .authorized, .provisional: return true
        case .notDetermined, .denied, .unsupported: return false
        }
    }

    var displayTitle: String {
        switch self {
        case .notDetermined: return "尚未请求"
        case .denied: return "未授权"
        case .authorized: return "已授权"
        case .provisional: return "临时授权"
        case .unsupported: return "不可用"
        }
    }
}

/// Description used by schedule applier / mock scheduler (no UIKit).
struct ReminderNotificationDescriptor: Equatable, Sendable {
    var identifier: String
    var title: String
    var body: String
    var hour: Int
    var minute: Int
    var kind: ReminderKind
}
