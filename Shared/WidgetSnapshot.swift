//
//  WidgetSnapshot.swift
//  Pepper Watch (shared with the widget extension)
//
//  A small summary of recent scans that the app writes to the App Group container
//  and the widgets read. Daily counts are stored raw so widgets compute the
//  "past 7 days" window at display time and never show a stale window.
//

import Foundation

nonisolated enum SharedContainer {
    static let appGroupID = "group.com.tristanlistanco.Pepper-Watch"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

nonisolated struct WidgetSnapshot: Codable, Sendable {
    nonisolated struct DailyCount: Codable, Sendable, Identifiable {
        var id: Date { date }
        let date: Date
        let aphid: Int
        let total: Int
        let scans: Int

        var rate: Double { total == 0 ? 0 : Double(aphid) / Double(total) }
    }

    /// Aggregates for a time window ending today.
    nonisolated struct WindowSummary: Sendable {
        let aphidLeaves: Int
        let totalLeaves: Int
        let scans: Int
        let daily: [DailyCount]

        var infestationRate: Double { totalLeaves == 0 ? 0 : Double(aphidLeaves) / Double(totalLeaves) }
        var severity: Severity? {
            totalLeaves == 0 ? nil : Severity(aphidCount: aphidLeaves, infestationRate: infestationRate)
        }
    }

    nonisolated struct FieldStatus: Codable, Sendable, Identifiable {
        /// Field UUID string, or `WidgetSnapshot.allFieldsID`.
        var id: String
        var name: String
        var locationName: String
        var latestScan: Date?
        /// One entry per day with scans, covering the last 30 days.
        var daily: [DailyCount]
        /// Field center and geofence radius, for the watch map. `nil` for "All Fields".
        var latitude: Double? = nil
        var longitude: Double? = nil
        var radiusMeters: Double? = nil

        /// Totals for the `days` ending today, or ending `offset` days earlier for comparisons.
        func window(days: Int = 7, offset: Int = 0, now: Date = .now, calendar: Calendar = .current) -> WindowSummary {
            let today = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -(days - 1) - offset, to: today) ?? now
            let end = calendar.date(byAdding: .day, value: 1 - offset, to: today) ?? now
            let inWindow = daily.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
            return WindowSummary(
                aphidLeaves: inWindow.reduce(0) { $0 + $1.aphid },
                totalLeaves: inWindow.reduce(0) { $0 + $1.total },
                scans: inWindow.reduce(0) { $0 + $1.scans },
                daily: inWindow
            )
        }
    }

    static let allFieldsID = "all"
    private static let storageKey = "widget.snapshot"

    var generatedAt: Date
    var overall: FieldStatus
    var fields: [FieldStatus]

    func status(forFieldID id: String?) -> FieldStatus {
        guard let id, id != Self.allFieldsID else { return overall }
        return fields.first { $0.id == id } ?? overall
    }

    static func load() -> WidgetSnapshot? {
        guard let data = SharedContainer.defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        SharedContainer.defaults.set(data, forKey: Self.storageKey)
    }

    /// Sample data for widget placeholders and previews.
    static var sample: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let rates = [(3, 14), (5, 16), (8, 18), (11, 20), (9, 22), (7, 21), (6, 19)]
        let daily = rates.enumerated().map { index, pair in
            DailyCount(
                date: calendar.date(byAdding: .day, value: index - 6, to: today) ?? today,
                aphid: pair.0,
                total: pair.1,
                scans: 4
            )
        }
        let field = FieldStatus(id: UUID().uuidString, name: "Field A", locationName: "Claveria", latestScan: .now, daily: daily)
        let overall = FieldStatus(id: allFieldsID, name: "All Fields", locationName: "", latestScan: .now, daily: daily)
        return WidgetSnapshot(generatedAt: .now, overall: overall, fields: [field])
    }
}
