//
//  FieldRelevance.swift
//  Pepper Watch (shared by every target)
//
//  When each field matters, for the Smart Stack: Smart Rotate on iPhone and iPad Home Screens,
//  and the watch's Smart Stack and relevant intents.
//

import CoreLocation
import Foundation
import RelevanceKit

/// Widget kinds of the iPhone and iPad widget extension, so the app can reload them by name.
nonisolated enum PhoneWidgetKind {
    static let fieldStatus = "FieldStatusWidget"
    static let fieldActions = "FieldActionsWidget"
    static let all = [fieldStatus, fieldActions]
}

nonisolated enum FieldRelevance {
    /// A field is due for scouting once this long has passed since its last scan.
    static let scoutingInterval: TimeInterval = 3 * 86_400

    nonisolated struct Context {
        let field: WidgetSnapshot.FieldStatus
        let relevance: RelevantContext
    }

    /// Where: at the field. `includeTiming` adds when: the morning a field is due for scouting,
    /// and the next few hours while a field is moderate or severe.
    static func contexts(for fields: [WidgetSnapshot.FieldStatus], now: Date = .now, includeTiming: Bool = true) -> [Context] {
        var contexts: [Context] = []
        for field in fields {
            if let latitude = field.latitude, let longitude = field.longitude {
                let region = CLCircularRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    // Small geofences are hard to detect reliably; give the Smart Stack a little margin.
                    radius: max(field.radiusMeters ?? 100, 100),
                    identifier: field.id
                )
                contexts.append(Context(field: field, relevance: .location(region)))
            }
            guard includeTiming else { continue }

            if let severity = field.window(now: now).severity, severity >= .moderate {
                contexts.append(Context(
                    field: field,
                    relevance: .date(interval: DateInterval(start: now, duration: 6 * 3600), kind: .informational)
                ))
            }
            if isDueForScouting(field, now: now), let morning = nextScoutingWindow(after: now) {
                contexts.append(Context(field: field, relevance: .date(interval: morning, kind: .informational)))
            }
        }
        return contexts
    }

    static func isDueForScouting(_ field: WidgetSnapshot.FieldStatus, now: Date = .now) -> Bool {
        now.timeIntervalSince(field.latestScan ?? .distantPast) >= scoutingInterval
    }

    /// How much a field's widget deserves the top of a Smart Stack right now (0…1): worse
    /// infestation ranks higher, and a field due for scouting at least surfaces as a reminder.
    static func score(for field: WidgetSnapshot.FieldStatus?, now: Date = .now) -> Float {
        guard let field else { return 0 }
        let severityScore: Float = switch field.window(now: now).severity {
        case .severe?: 1
        case .moderate?: 0.7
        case .low?: 0.4
        case .clear?: 0.2
        case nil: 0.1
        }
        return isDueForScouting(field, now: now) ? max(severityScore, 0.5) : severityScore
    }

    /// The next 6–10 AM window, when leaves are easiest to scout.
    static func nextScoutingWindow(after now: Date, calendar: Calendar = .current) -> DateInterval? {
        guard var start = calendar.date(bySettingHour: 6, minute: 0, second: 0, of: now),
              let todayEnd = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)
        else { return nil }
        if now >= todayEnd {
            start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        }
        return DateInterval(start: max(start, now), end: calendar.date(byAdding: .hour, value: 4, to: start) ?? start)
    }
}
