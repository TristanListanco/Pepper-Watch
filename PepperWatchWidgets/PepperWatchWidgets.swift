//
//  PepperWatchWidgets.swift
//  PepperWatchWidgets
//
//  Home Screen and Lock Screen widgets showing a field's aphid status for the past 7 days.
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Configuration

struct WidgetFieldEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Field"
    static let defaultQuery = WidgetFieldQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct WidgetFieldQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetFieldEntity] {
        options().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetFieldEntity] {
        options()
    }

    func defaultResult() async -> WidgetFieldEntity? {
        options().first
    }

    /// The fields the app last wrote to the shared snapshot. Each widget shows one field.
    private func options() -> [WidgetFieldEntity] {
        (WidgetSnapshot.load()?.fields ?? []).map { WidgetFieldEntity(id: $0.id, name: $0.name) }
    }
}

struct SelectFieldIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Select Field"
    static let description = IntentDescription("Choose which field the widget shows.")

    @Parameter(title: "Field")
    var field: WidgetFieldEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$field)")
    }
}

// MARK: - Timeline

struct FieldStatusEntry: TimelineEntry {
    let date: Date
    let status: WidgetSnapshot.FieldStatus
    let fields: [WidgetSnapshot.FieldStatus]
}

struct FieldStatusProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> FieldStatusEntry {
        let sample = WidgetSnapshot.sample
        return FieldStatusEntry(date: .now, status: sample.fields.first ?? sample.overall, fields: sample.fields)
    }

    func snapshot(for configuration: SelectFieldIntent, in context: Context) async -> FieldStatusEntry {
        entry(for: configuration, preview: context.isPreview)
    }

    func timeline(for configuration: SelectFieldIntent, in context: Context) async -> Timeline<FieldStatusEntry> {
        // The app reloads timelines after new scans; refresh hourly so the 7-day window rolls over.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [entry(for: configuration, preview: false)], policy: .after(next))
    }

    private func entry(for configuration: SelectFieldIntent, preview: Bool) -> FieldStatusEntry {
        let snapshot = WidgetSnapshot.load() ?? (preview ? .sample : WidgetSnapshot.empty)
        // Default to the first field; "All Fields" only shows before any field exists.
        return FieldStatusEntry(
            date: .now,
            status: snapshot.status(forFieldID: configuration.field?.id ?? snapshot.fields.first?.id),
            fields: snapshot.fields
        )
    }
}

private extension WidgetSnapshot {
    static var empty: WidgetSnapshot {
        let overall = FieldStatus(id: allFieldsID, name: "All Fields", locationName: "", latestScan: nil, daily: [])
        return WidgetSnapshot(generatedAt: .now, overall: overall, fields: [])
    }
}

// MARK: - Widget

struct FieldStatusWidgetEntryView: View {
    let entry: FieldStatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        FieldStatusWidgetView(status: entry.status, family: family, now: entry.date)
            .containerBackground(.clear, for: .widget)
            .widgetURL(.pepperWatch("insights", fieldID: entry.status.id))
    }
}

struct FieldStatusWidget: Widget {
    let kind = "FieldStatusWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: SelectFieldIntent.self, provider: FieldStatusProvider()) { entry in
            FieldStatusWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Field Status")
        .description("A field's aphid infestation and severity over the past 7 days, on your Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Field Actions (interactive)

struct FieldActionsEntry: TimelineEntry {
    let date: Date
    let options: [WidgetSnapshot.FieldStatus]
    let index: Int
}

struct FieldActionsProvider: TimelineProvider {
    func placeholder(in context: Context) -> FieldActionsEntry {
        let sample = WidgetSnapshot.sample
        return FieldActionsEntry(date: .now, options: WidgetActionsState.options(in: sample), index: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (FieldActionsEntry) -> Void) {
        completion(entry(preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FieldActionsEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [entry(preview: false)], policy: .after(next)))
    }

    private func entry(preview: Bool) -> FieldActionsEntry {
        let snapshot = WidgetSnapshot.load() ?? (preview ? .sample : nil)
        let options = WidgetActionsState.options(in: snapshot)
        let index = options.isEmpty ? 0 : WidgetActionsState.selectedIndex % options.count
        return FieldActionsEntry(date: .now, options: options, index: index)
    }
}

struct FieldActionsWidgetEntryView: View {
    let entry: FieldActionsEntry
    @Environment(\.widgetFamily) private var family

    private var current: WidgetSnapshot.FieldStatus? {
        entry.options.isEmpty ? nil : entry.options[entry.index]
    }

    var body: some View {
        FieldActionsWidgetView(options: entry.options, index: entry.index, family: family, now: entry.date)
            .containerBackground(for: .widget) {
                WidgetBackground(severity: current?.window(now: entry.date).severity)
            }
            // Small widgets have one tap target: open the scanner for the shown field.
            .widgetURL(.pepperWatch("scan", fieldID: current?.id))
    }
}

struct FieldActionsWidget: Widget {
    let kind = "FieldActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FieldActionsProvider()) { entry in
            FieldActionsWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Field Actions")
        .description("Flip between fields and jump straight into scanning or insights.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct PepperWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FieldStatusWidget()
        FieldActionsWidget()
    }
}
