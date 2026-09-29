//
//  PepperWatchWatchWidgets.swift
//  PepperWatchWatchWidgets
//
//  Smart Stack widgets. RelevantContext tells the Smart Stack when they matter: at one of your
//  fields, the morning a field is due for scouting, and while a field is moderate or severe.
//

import AppIntents
import SwiftUI
import WidgetKit

/// Smart Stack relevance built from the shared field contexts.
private func widgetRelevance(includeTiming: Bool) -> WidgetRelevance<WatchFieldIntent> {
    WidgetRelevance(WatchRelevance.contexts(includeTiming: includeTiming).map {
        WidgetRelevanceAttribute(configuration: WatchFieldIntent(field: WatchFieldEntity($0.field)), context: $0.relevance)
    })
}

// MARK: - Providers

struct FieldStatusProvider: AppIntentTimelineProvider {
    /// No presets: on watchOS 26 and later, an empty list lets people configure the widget
    /// themselves, choosing the field and metric right on the watch.
    func recommendations() -> [AppIntentRecommendation<WatchFieldIntent>] {
        []
    }

    func placeholder(in context: Context) -> FieldEntry {
        .sample
    }

    func snapshot(for configuration: WatchFieldIntent, in context: Context) async -> FieldEntry {
        context.isPreview && WatchStore.payload == nil ? .sample : .current(configuration)
    }

    func timeline(for configuration: WatchFieldIntent, in context: Context) async -> Timeline<FieldEntry> {
        // The watch app reloads widgets when the iPhone syncs; refresh hourly so the 7-day window rolls over.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        return Timeline(entries: [.current(configuration)], policy: .after(next))
    }

    func relevance() async -> WidgetRelevance<WatchFieldIntent> {
        widgetRelevance(includeTiming: true)
    }
}

struct AtFieldProvider: RelevanceEntriesProvider {
    /// Location only: this widget exists to greet you at the field.
    func relevance() async -> WidgetRelevance<WatchFieldIntent> {
        widgetRelevance(includeTiming: false)
    }

    func entry(configuration: WatchFieldIntent, context: Context) async throws -> FieldEntry {
        context.isPreview && WatchStore.payload == nil ? .sample : .current(configuration)
    }

    func placeholder(context: Context) -> FieldEntry {
        .sample
    }
}

// MARK: - Widgets

struct FieldStatusWatchWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: WatchWidgetKind.fieldStatus, intent: WatchFieldIntent.self, provider: FieldStatusProvider()) { entry in
            FieldWidgetView(entry: entry)
        }
        .configurationDisplayName("Field Status")
        .description("A field's infestation, leaf health or scans over the past 7 days.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

/// Needs no setup: appears in the Smart Stack by itself when you arrive at one of your fields.
struct AtFieldWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: WatchWidgetKind.atField, provider: AtFieldProvider()) { entry in
            FieldWidgetView(entry: entry)
        }
        .configurationDisplayName("At Your Field")
        .description("Shows a field's status when you arrive at it.")
    }
}

@main
struct PepperWatchWatchWidgets: WidgetBundle {
    var body: some Widget {
        FieldStatusWatchWidget()
        AtFieldWidget()
    }
}
