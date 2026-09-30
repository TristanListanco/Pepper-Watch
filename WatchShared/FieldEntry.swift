//
//  FieldEntry.swift
//  Pepper Watch (shared by the Apple Watch app and its widgets)
//

import Foundation
import WidgetKit

nonisolated struct FieldEntry: TimelineEntry, RelevanceEntry {
    let date: Date
    let status: WidgetSnapshot.FieldStatus?
    let metric: WidgetMetric
    /// The iPhone's Apple Intelligence headline for the field.
    let headline: String?
    let score: Float

    /// Worse infestation ranks the widget higher in the Smart Stack.
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: score)
    }

    /// The configured field, or the first field when none is chosen yet.
    static func current(_ configuration: WatchFieldIntent, now: Date = .now) -> FieldEntry {
        current(fieldID: configuration.field?.id, metric: configuration.metric, now: now)
    }

    static func current(fieldID: String?, metric: WidgetMetric = .infestation, now: Date = .now) -> FieldEntry {
        let fields = WatchStore.ordered(WatchStore.payload?.snapshot.fields ?? [])
        guard let payload = WatchStore.payload,
              let status = fields.first(where: { $0.id == fieldID }) ?? fields.first
        else {
            return FieldEntry(date: now, status: nil, metric: metric, headline: nil, score: 0)
        }
        let stats = ScopeStats(status, now: now)
        let score: Float = switch stats.current.severity {
        case .severe?: 1
        case .moderate?: 0.7
        case .low?: 0.4
        case .clear?: 0.2
        case nil: 0.1
        }
        return FieldEntry(
            date: now,
            status: status,
            metric: metric,
            headline: payload.highlights[status.id]?.headline,
            score: score
        )
    }

    static var sample: FieldEntry {
        FieldEntry(date: .now, status: WidgetSnapshot.sample.fields.first, metric: .infestation, headline: "Aphid damage is rising", score: 0.7)
    }
}
