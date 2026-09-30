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
        var date = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: now) ?? now
        if date <= now { date = calendar.date(byAdding: .day, value: 1, to: date) ?? date }
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: date, userInfo: taskID as NSString) { _ in }
    }
}
