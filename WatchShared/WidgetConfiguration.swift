//
//  WidgetConfiguration.swift
//  Pepper Watch (shared by the Apple Watch app and its widgets)
//
//  What a watch widget shows, and when the Smart Stack should put it forward.
//

import AppIntents
import CoreLocation
import RelevanceKit

// MARK: - Configuration

struct WatchFieldEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Field"
    static let defaultQuery = WatchFieldQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: DisplayRepresentation.Image(systemName: "leaf.fill"))
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ status: WidgetSnapshot.FieldStatus) {
        self.init(id: status.id, name: status.name)
    }
}

nonisolated struct WatchFieldQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WatchFieldEntity] {
        Self.fields().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WatchFieldEntity] {
        Self.fields()
    }

    func defaultResult() async -> WatchFieldEntity? {
        Self.fields().first
    }

    /// The fields the iPhone last synced.
    static func fields() -> [WatchFieldEntity] {
        (WatchStore.payload?.snapshot.fields ?? []).map(WatchFieldEntity.init)
    }
}

enum WidgetMetric: String, AppEnum {
    case infestation, leafHealth, scans

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"
    static let caseDisplayRepresentations: [WidgetMetric: DisplayRepresentation] = [
        .infestation: DisplayRepresentation(title: "Infestation Rate", image: DisplayRepresentation.Image(systemName: "ant.fill")),
        .leafHealth: DisplayRepresentation(title: "Leaf Health", image: DisplayRepresentation.Image(systemName: "leaf.fill")),
        .scans: DisplayRepresentation(title: "Scans", image: DisplayRepresentation.Image(systemName: "camera.viewfinder")),
    ]
}

/// Edited right on the watch (watchOS 26+): which field, and which number to show.
struct WatchFieldIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Field Status"
    static let description = IntentDescription("Choose a field and what to show for it.")

    @Parameter(title: "Field")
    var field: WatchFieldEntity?

    @Parameter(title: "Show", default: .infestation)
    var metric: WidgetMetric

    init() {}

    init(field: WatchFieldEntity, metric: WidgetMetric = .infestation) {
        self.field = field
        self.metric = metric
    }

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$metric) for \(\.$field)")
    }
}

// MARK: - Relevance

/// When each field matters, as Smart Stack contexts.
nonisolated enum WatchRelevance {
    /// A field is due for scouting once this long has passed since its last scan.
    static let scoutingInterval: TimeInterval = 3 * 86_400

    struct Context {
        let field: WidgetSnapshot.FieldStatus
        let relevance: RelevantContext
    }

    /// Where: at the field. `includeTiming` adds when: the morning a field is due for scouting,
    /// and the next few hours while a field is moderate or severe.
    static func contexts(now: Date = .now, includeTiming: Bool = true) -> [Context] {
        let fields = WatchStore.payload?.snapshot.fields ?? []
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
            let lastScan = field.latestScan ?? .distantPast
            if now.timeIntervalSince(lastScan) >= scoutingInterval, let morning = nextScoutingWindow(after: now) {
                contexts.append(Context(field: field, relevance: .date(interval: morning, kind: .informational)))
            }
        }
        return contexts
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
