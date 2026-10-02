//
//  ContentView.swift
//  Pepper Watch (Apple Watch)
//
//  watchOS navigation, each container where it fits:
//  - NavigationSplitView: your fields (source list) and a field's insights (detail). The app
//    opens on the field you viewed last; the list is one tap away.
//  - TabView: the detail's pages, paged with the Digital Crown.
//  - NavigationStack: inside the detail, for drilling into a day-by-day breakdown.
//

import CoreLocation
import SwiftUI
import TipKit
import WidgetKit

struct ContentView: View {
    @Environment(PhoneConnection.self) private var phone
    @AppStorage(WatchFieldSelection.key) private var savedField = ""
    @State private var selection: String?

    init() {
        // Always start with a selection so the app opens straight into a field's insights.
        let fields = WatchStore.ordered(WatchStore.payload?.snapshot.fields ?? [])
        let saved = UserDefaults.standard.string(forKey: WatchFieldSelection.key)
        var initial = fields.first(where: { $0.id == saved })?.id ?? fields.first?.id
        #if DEBUG
        // `-PWWatchScope list|firstField` opens the field list or the first field, for screenshots.
        switch UserDefaults.standard.string(forKey: "PWWatchScope") {
        case "list": initial = nil
        case "firstField": initial = fields.first?.id
        default: break
        }
        #endif
        _selection = State(initialValue: initial)
    }

    var body: some View {
        Group {
            #if DEBUG
            if UserDefaults.standard.bool(forKey: "PWWatchWidgetGallery") {
                WidgetGallery()
            } else {
                root
            }
            #else
            root
            #endif
        }
    }

    @ViewBuilder
    private var root: some View {
        if let payload = phone.payload {
            NavigationSplitView {
                FieldListView(payload: payload, selection: $selection)
            } detail: {
                if let status = payload.snapshot.fields.first(where: { $0.id == selection }) {
                    InsightsPager(status: status, trends: payload.trends?[status.id])
                        // Start at the summary whenever the field changes.
                        .id(status.id)
                } else {
                    ContentUnavailableView {
                        Label("No Fields", systemImage: "leaf")
                    } description: {
                        Text("Create a field in Pepper Watch on your iPhone.")
                    }
                }
            }
            .onChange(of: selection) { _, newValue in
                if let newValue { savedField = newValue }
            }
            // The Field Status control opens the app on its field.
            .onChange(of: savedField) { _, id in
                if !id.isEmpty, selection != id { selection = id }
            }
            // Smart Stack widgets open the field they show.
            .onOpenURL { url in
                guard url.scheme == "pepperwatch", url.host == "field",
                      let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "id" })?.value
                else { return }
                selection = id
            }
        } else {
            NavigationStack {
                WaitingForPhoneView()
            }
        }
    }
}

// MARK: - Field list

/// The source list on plain black: each field is a card in its status color, with no title or
/// toolbar so the cards get the room. Pull down to sync with iPhone.
private struct FieldListView: View {
    let payload: WatchPayload
    @Binding var selection: String?
    @Environment(PhoneConnection.self) private var phone
    @State private var locationAccess = LocationAccess()
    /// The order set by dragging fields in the list (watchOS 27), shared with the widgets.
    @AppStorage(WatchStore.fieldOrderKey, store: SharedContainer.defaults) private var orderRaw = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fields = WatchStore.ordered(payload.snapshot.fields, order: orderRaw)
        List(selection: $selection) {
            TipView(ReorderFieldsTip())
                .listRowBackground(Color.clear)
            if fields.isEmpty {
                Text("Create a field in Pepper Watch on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // Touch and hold a field, then drag it; the first field is the one the app opens on.
            ForEach(fields) { field in
                NavigationLink(value: field.id) {
                    FieldRow(status: field)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                        // The card is part of the row, so it moves with the row while dragging;
                        // reordering doesn't keep list row backgrounds.
                        .background(FieldCard(severity: field.window().severity))
                }
            }
            .reorderable()
            // Applied to the reorderable rows as a whole; the card inside each row fills it.
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                if locationAccess.canAsk {
                    Button("Show at My Fields", systemImage: "location.fill") {
                        locationAccess.request()
                    }
                    .foregroundStyle(.primary)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if locationAccess.canAsk {
                        Text("Lets the Smart Stack show a field when you arrive at it.")
                            .foregroundStyle(.secondary)
                    }
                    Text("Synced \(payload.snapshot.generatedAt, format: .relative(presentation: .named))")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .reorderContainer(for: WidgetSnapshot.FieldStatus.self) { difference in
            let destination: String? = switch difference.destination.position {
            case .before(let id): id
            case .end: nil
            }
            withAnimation(.smooth) {
                orderRaw = WatchStore.reordering(fields, sources: Array(difference.sources), before: destination)
            }
            ReorderFieldsTip().invalidate(reason: .actionPerformed)
            // Your Fields shows the first three in this order.
            WidgetCenter.shared.reloadTimelines(ofKind: WatchWidgetKind.yourFields)
        }
        // With Reduce Motion, reordered fields settle without animating.
        .transaction { if reduceMotion { $0.animation = nil } }
        // A tap on the wrist when a field lands in its new place.
        .sensoryFeedback(.impact(weight: .light), trigger: orderRaw)
        .task(id: fields.count) { ReorderFieldsTip.fieldCount = fields.count }
        .refreshable { await phone.requestUpdate() }
    }
}

/// A field card in a rich gradient of its status color, darkened toward the bottom so white text
/// stays readable on every status. Fields without scans this week get the neutral quaternary fill.
private struct FieldCard: View {
    let severity: Severity?
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if let severity, isLuminanceReduced {
            // Always On: a deep tint of the status color instead of the bright gradient.
            RoundedRectangle(cornerRadius: 20).fill(severity.color.mix(with: .black, by: 0.75))
        } else if let severity {
            RoundedRectangle(cornerRadius: 20).fill(
                LinearGradient(
                    colors: [severity.color.mix(with: .black, by: 0.25), severity.color.mix(with: .black, by: 0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            RoundedRectangle(cornerRadius: 20).fill(.quaternary)
        }
    }
}

/// The field's name, its infested share below, and how long since it was scanned in the corner.
private struct FieldRow: View {
    let status: WidgetSnapshot.FieldStatus
    /// The card's color is the only other status cue, so this adds the severity symbol.
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        let window = status.window()
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                if differentiateWithoutColor, let severity = window.severity {
                    Image(systemName: severity.symbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                Text(status.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let latest = status.latestScan {
                    Text(compactAge(since: latest))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(window.totalLeaves == 0 ? "—" : window.infestationRate.percentText)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .foregroundStyle(window.totalLeaves == 0 ? .secondary : .primary)
        }
        .padding(.vertical, 6)
        // The status is carried by the card color, so spell it out for VoiceOver.
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilitySummary(window))
    }

    private func accessibilitySummary(_ window: WidgetSnapshot.WindowSummary) -> String {
        var parts = [window.totalLeaves == 0 ? "No scans this week" : "\(window.infestationRate.percentText) infested"]
        if let severity = window.severity { parts.append(severity.title) }
        if let latest = status.latestScan { parts.append("scanned \(latest.formatted(.relative(presentation: .named)))") }
        return parts.joined(separator: ", ")
    }
}

/// "now", "5m", "17h", "4d", "3w": short enough for a card corner, without "ago".
private func compactAge(since date: Date, now: Date = .now) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<60: return "now"
    case ..<3600: return "\(Int(seconds / 60))m"
    case ..<86_400: return "\(Int(seconds / 3600))h"
    case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d"
    default: return "\(Int(seconds / (7 * 86_400)))w"
    }
}

// MARK: - Waiting

private struct WaitingForPhoneView: View {
    @Environment(PhoneConnection.self) private var phone

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.brand)
                    // Breathes while asking the iPhone for data (SF Symbols 6).
                    .symbolEffect(.breathe, isActive: phone.isRequesting)
                    .accessibilityHidden(true)
                Text("Open Pepper Watch on iPhone")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("Your fields and insights sync from your paired iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try Again", systemImage: "arrow.clockwise") {
                    Task { await phone.requestUpdate() }
                }
                .buttonStyle(.glass)
                .disabled(phone.isRequesting)
                .handGestureShortcut(.primaryAction)
            }
            .scenePadding(.horizontal)
        }
    }
}

// MARK: - Location for the Smart Stack

/// When In Use location access, which lets the Smart Stack surface a field's widget when you arrive there.
@Observable
private final class LocationAccess: NSObject, CLLocationManagerDelegate {
    private(set) var canAsk = false
    @ObservationIgnored private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        canAsk = manager.authorizationStatus == .notDetermined
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let notDetermined = manager.authorizationStatus == .notDetermined
        Task { @MainActor in self.canAsk = notDetermined }
    }
}
