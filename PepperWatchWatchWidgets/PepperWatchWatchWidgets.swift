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

// MARK: - Your Fields (accessory widget group)

struct YourFieldsEntry: TimelineEntry {
    let date: Date
    let fields: [WidgetSnapshot.FieldStatus]

    /// The field most in need of attention decides where the card ranks in the Smart Stack.
    var relevance: TimelineEntryRelevance? {
        TimelineEntryRelevance(score: fields.map { FieldRelevance.score(for: $0, now: date) }.max() ?? 0)
    }

    static var current: YourFieldsEntry {
        // The first three in the order set on the watch.
        YourFieldsEntry(date: .now, fields: Array(WatchStore.ordered(WatchStore.payload?.snapshot.fields ?? []).prefix(3)))
    }
}

struct YourFieldsProvider: TimelineProvider {
    func placeholder(in context: Context) -> YourFieldsEntry {
        YourFieldsEntry(date: .now, fields: WidgetSnapshot.sample.fields)
    }

    func getSnapshot(in context: Context, completion: @escaping (YourFieldsEntry) -> Void) {
        completion(context.isPreview && WatchStore.payload == nil ? placeholder(in: context) : .current)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<YourFieldsEntry>) -> Void) {
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        completion(Timeline(entries: [.current], policy: .after(next)))
    }
}

/// Each field as a small gauge of this week's infestation, in its severity color.
struct YourFieldsView: View {
    let entry: YourFieldsEntry

    var body: some View {
        Group {
            if entry.fields.isEmpty {
                Label("Open Pepper Watch", systemImage: "leaf.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                AccessoryWidgetGroup("Your Fields", systemImage: "leaf.fill") {
                    ForEach(entry.fields) { field in
                        let week = field.window(now: entry.date)
                        // Each gauge opens its own field.
                        Link(destination: .watchField(field.id)) {
                            Gauge(value: week.infestationRate) {
                                Text(field.name)
                            } currentValueLabel: {
                                Text(week.totalLeaves == 0 ? "—" : "\(Int((week.infestationRate * 100).rounded()))")
                            }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(week.severity?.color ?? .secondary)
                        }
                        .accessibilityLabel("\(field.name), \(week.totalLeaves == 0 ? "no scans this week" : "\(week.infestationRate.percentText) infested")")
                    }
                }
                .accessoryWidgetGroupStyle(.circular)
            }
        }
        .containerBackground(Color.brand.gradient.opacity(0.4), for: .widget)
    }
}

struct YourFieldsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.yourFields, provider: YourFieldsProvider()) { entry in
            YourFieldsView(entry: entry)
        }
        .configurationDisplayName("Your Fields")
        .description("Up to three fields' infestation at a glance, in your watch order.")
        .supportedFamilies([.accessoryRectangular])
    }
}

// MARK: - Control (watchOS 26)

/// What the control shows: the field, its infestation rate this week and its severity.
struct FieldControlValue {
    let field: WatchFieldEntity?
    let name: String
    let rate: String
    let symbol: String
}

struct FieldControlProvider: AppIntentControlValueProvider {
    func previewValue(configuration: FieldControlIntent) -> FieldControlValue {
        FieldControlValue(field: nil, name: configuration.field?.name ?? "Field A", rate: "12%", symbol: Severity.low.symbol)
    }

    func currentValue(configuration: FieldControlIntent) async throws -> FieldControlValue {
        let fields = WatchStore.payload?.snapshot.fields ?? []
        guard let status = fields.first(where: { $0.id == configuration.field?.id }) ?? fields.first else {
            return FieldControlValue(field: nil, name: "Pepper Watch", rate: "No fields", symbol: "leaf")
        }
        let week = status.window()
        return FieldControlValue(
            field: WatchFieldEntity(status),
            name: status.name,
            rate: week.totalLeaves == 0 ? "No scans" : "\(week.infestationRate.percentText) infested",
            symbol: week.severity?.symbol ?? "leaf.fill"
        )
    }
}

/// A field's infestation at a glance in Control Center, the Smart Stack or on the Action button;
/// tapping it opens that field's insights.
struct FieldStatusControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: WatchWidgetKind.fieldControl, provider: FieldControlProvider()) { value in
            ControlWidgetButton(action: OpenFieldIntent(field: value.field)) {
                Label {
                    Text(value.name)
                    // A second line becomes the control's value.
                    Text(value.rate)
                } icon: {
                    Image(systemName: value.symbol)
                }
            }
        }
        .displayName("Field Status")
        .description("A field's infestation this week. Opens its insights.")
    }
}

@main
struct PepperWatchWatchWidgets: WidgetBundle {
    var body: some Widget {
        FieldStatusWatchWidget()
        AtFieldWidget()
        YourFieldsWidget()
        FieldStatusControl()
    }
}
