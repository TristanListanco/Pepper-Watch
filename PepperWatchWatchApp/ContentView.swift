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

struct ContentView: View {
    @Environment(PhoneConnection.self) private var phone
    @AppStorage("watch.selectedField") private var savedField = ""
    @State private var selection: String?

    init() {
        // Always start with a selection so the app opens straight into a field's insights.
        let fields = WatchStore.payload?.snapshot.fields ?? []
        let saved = UserDefaults.standard.string(forKey: "watch.selectedField")
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
                    InsightsPager(status: status, highlight: payload.highlights[status.id])
                        // Start at the summary whenever the field changes.
                        .id(status.id)
                } else {
                    ContentUnavailableView {
                        Label("No Fields", systemImage: "leaf")
                    } description: {
                        Text("Create a field in Pepper Watch on your iPhone.")
                    }
                    .containerBackground(Color.brand.gradient, for: .navigation)
                }
            }
            .onChange(of: selection) { _, newValue in
                if let newValue { savedField = newValue }
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

/// The source list: no title, so the shorter bar leaves more room for comparing fields.
private struct FieldListView: View {
    let payload: WatchPayload
    @Binding var selection: String?
    @Environment(PhoneConnection.self) private var phone
    @State private var locationAccess = LocationAccess()

    var body: some View {
        List(selection: $selection) {
            if payload.snapshot.fields.isEmpty {
                Text("Create a field in Pepper Watch on your iPhone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(payload.snapshot.fields) { field in
                NavigationLink(value: field.id) {
                    FieldRow(status: field)
                }
            }

            Section {
                if locationAccess.canAsk {
                    Button("Show at My Fields", systemImage: "location.fill") {
                        locationAccess.request()
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if locationAccess.canAsk {
                        Text("Lets the Smart Stack show a field when you arrive at it.")
                    }
                    Text("Synced \(payload.snapshot.generatedAt, format: .relative(presentation: .named))")
                }
            }
        }
        .containerBackground(Color.brand.gradient, for: .navigation)
        .refreshable { await phone.requestUpdate() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Sync with iPhone", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await phone.requestUpdate() }
                }
                .symbolEffect(.rotate, isActive: phone.isRequesting)
                .tint(Color.brand)
                .disabled(phone.isRequesting)
            }
        }
    }
}

/// Name, severity and last scan on the left; the infestation ring on the right for comparing fields at a glance.
private struct FieldRow: View {
    let status: WidgetSnapshot.FieldStatus

    var body: some View {
        let window = status.window()
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(status.name)
                    .font(.headline)
                    .lineLimit(1)
                if let severity = window.severity {
                    Label {
                        Text(severity.title)
                    } icon: {
                        Image(systemName: severity.symbol)
                            .foregroundStyle(severity.color)
                    }
                    .font(.caption2.weight(.semibold))
                } else {
                    Text("No scans this week")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let latest = status.latestScan {
                    Text(latest, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            ZStack {
                InfestationRing(progress: window.infestationRate, animatesIn: false)
                Text(window.totalLeaves == 0 ? "—" : "\(Int((window.infestationRate * 100).rounded()))")
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
            }
            .frame(width: 42, height: 42)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityValue(window.totalLeaves == 0 ? "No scans this week" : "\(window.infestationRate.percentText) infested")
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
                    .symbolEffect(.pulse, isActive: phone.isRequesting)
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
        .containerBackground(Color.brand.gradient, for: .navigation)
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
