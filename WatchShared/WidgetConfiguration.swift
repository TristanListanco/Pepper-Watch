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
        // The watch's own order, so a new widget starts on the field placed first.
        WatchStore.ordered(WatchStore.payload?.snapshot.fields ?? []).map(WatchFieldEntity.init)
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

// MARK: - Control (watchOS 26)

/// Which field the Field Status control shows and opens.
struct FieldControlIntent: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "Field Status"
    static let description = IntentDescription("Choose the field the control shows.")

    @Parameter(title: "Field")
    var field: WatchFieldEntity?

    init() {}
}

/// Opens the watch app on a field. Controls run it in the app, which switches to that field.
struct OpenFieldIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Field"
    static let description = IntentDescription("Opens a field's insights in Pepper Watch.")
    static let supportedModes: IntentModes = .foreground
    static let isDiscoverable = false

    @Parameter(title: "Field")
    var field: WatchFieldEntity?

    init() {}

    init(field: WatchFieldEntity?) {
        self.field = field
    }

    func perform() async throws -> some IntentResult {
        // The app follows this setting to the field.
        if let id = field?.id {
            UserDefaults.standard.set(id, forKey: WatchFieldSelection.key)
        }
        return .result()
    }
}

/// The field the watch app shows, shared by the app and the control's intent.
nonisolated enum WatchFieldSelection {
    static let key = "watch.selectedField"
}

// MARK: - Relevance

/// When each field matters on the watch: the shared Smart Stack rules over the synced fields.
nonisolated enum WatchRelevance {
    static func contexts(now: Date = .now, includeTiming: Bool = true) -> [FieldRelevance.Context] {
        FieldRelevance.contexts(for: WatchStore.payload?.snapshot.fields ?? [], now: now, includeTiming: includeTiming)
    }
}
