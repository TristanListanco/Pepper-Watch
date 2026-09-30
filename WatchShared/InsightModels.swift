//
//  InsightModels.swift
//  Pepper Watch (Apple Watch)
//

import SwiftUI

extension Color {
    /// Class colors from the iPhone app, in their dark-mode steps for the watch's black background.
    static let aphid = Color(red: 0.922, green: 0.408, blue: 0.204)    // #EB6834
    static let healthy = Color(red: 0.106, green: 0.686, blue: 0.478)  // #1BAF7A
    static let brand = Color(red: 0.302, green: 0.729, blue: 0.353)    // #4DBA5A
}

/// One page of the Digital Crown pager, in scroll order.
enum InsightPage: Hashable {
    case summary, infestation, leafHealth, scans, location

    var title: String {
        switch self {
        case .summary: "Summary"
        case .infestation: "Infestation Rate"
        case .leafHealth: "Leaf Health"
        case .scans: "Scans"
        case .location: "Location"
        }
    }

    var symbol: String {
        switch self {
        case .summary: "leaf.fill"
        case .infestation: "ant.fill"
        case .leafHealth: "leaf.fill"
        case .scans: "camera.viewfinder"
        case .location: "mappin.and.ellipse"
        }
    }

    /// Same metric colors as the iPhone Insights tab, so each page keeps its identity.
    var tint: Color {
        switch self {
        case .summary: .brand
        case .infestation: .aphid
        case .leafHealth: .healthy
        case .scans: .brand
        case .location: .teal
        }
    }
}

/// Past-7-days numbers for one scope, computed from the iPhone's daily counts.
nonisolated struct ScopeStats {
    struct Day: Identifiable {
        let date: Date
        let aphid: Int
        let total: Int
        let scans: Int

        var id: Date { date }
        var rate: Double? { total == 0 ? nil : Double(aphid) / Double(total) }
    }

    let current: WidgetSnapshot.WindowSummary
    let previous: WidgetSnapshot.WindowSummary
    /// The last seven calendar days, including days without scans.
    let days: [Day]

    init(_ status: WidgetSnapshot.FieldStatus, now: Date = .now, calendar: Calendar = .current) {
        current = status.window(now: now, calendar: calendar)
        previous = status.window(offset: 7, now: now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        days = (0..<7).reversed().map { back in
            let date = calendar.date(byAdding: .day, value: -back, to: today) ?? today
            let match = status.daily.first { calendar.isDate($0.date, inSameDayAs: date) }
            return Day(date: date, aphid: match?.aphid ?? 0, total: match?.total ?? 0, scans: match?.scans ?? 0)
        }
    }

    var hasLeaves: Bool { current.totalLeaves > 0 }
    var healthyLeaves: Int { current.totalLeaves - current.aphidLeaves }

    /// Change in infestation from the previous 7 days, in percentage points.
    var change: Double? {
        guard current.totalLeaves > 0, previous.totalLeaves > 0 else { return nil }
        return (current.infestationRate - previous.infestationRate) * 100
    }
}

extension Double {
    nonisolated var percentText: String { formatted(.percent.precision(.fractionLength(0))) }
}
