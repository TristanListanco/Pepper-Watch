//
//  DailyRefresh.swift
//  Pepper Watch (Apple Watch)
//
//  A background app refresh each morning (watchOS background tasks), so widgets and Smart Stack
//  relevance stay current on days the iPhone doesn't sync.
//

import Foundation
import WatchKit

enum DailyRefresh {
    /// Passed as the refresh's user info, which is how SwiftUI routes it to the app's handler.
    static let taskID = "com.tristanlistanco.Pepper-Watch.watchkitapp.daily"

    /// Asks for a run a little before the 6–10 AM scouting window; watchOS picks the exact time.
    /// Only one refresh can be pending, so this replaces any earlier request.
    static func schedule(now: Date = .now, calendar: Calendar = .current) {
        // userInfo takes an NSSecureCoding object.
        // swiftlint:disable:next legacy_objc_type
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: nextRun(after: now, calendar: calendar), userInfo: taskID as NSString) { _ in }
    }

    /// The next 5 AM: today's if it's still ahead, otherwise tomorrow's.
    static func nextRun(after now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: now) ?? now
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
