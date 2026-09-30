//
//  FieldsHomeView.swift
//  Pepper Watch
//
//  Scan tab home: detects where the device is and recommends the field to scan.
//

import AppIntents
import CoreLocation
import CoreSpotlight
import MapKit
import SwiftData
import SwiftUI

struct FieldsHomeView: View {
    let fields: [Field]
    let onScan: (Field) -> Void
    let onNewField: () -> Void
    let onEdit: (Field) -> Void

    @Environment(LocationProvider.self) private var location
    @Environment(GeofenceService.self) private var geofence
    @Environment(\.modelContext) private var modelContext
    @Environment(\.systemLogger) private var logger
    @Environment(\.widgetSync) private var widgetSync
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \DetectionEvent.timestamp, order: .reverse) private var events: [DetectionEvent]
    @State private var pendingDeletion: Field?
    @State private var renaming: Field?
    @State private var draftName = ""

    /// Latest scan and scan count per field, recomputed whenever an event is inserted or deleted.
    private var activity: [UUID: FieldActivity] {
        var result: [UUID: FieldActivity] = [:]
        for event in events {
            guard let id = event.field?.id else { continue }
            var entry = result[id] ?? FieldActivity()
            if entry.latest == nil { entry.latest = event }
            if entry.severity == nil { entry.severity = event.severity }
            result[id] = entry
        }
        return result
    }

    /// Fields ordered by distance when a fix is available, otherwise by creation date.
    private var sortedFields: [Field] {
        guard let current = location.lastLocation else { return fields }
        return fields.sorted {
            current.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < current.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if horizontalSizeClass == .regular {
                    // iPad: recommendation and map side by side.
                    HStack(alignment: .top, spacing: 16) {
                        // Stretch the card to the row height so it lines up with the map.
                        recommendationCard
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .glassEffect(.regular, in: .rect(cornerRadius: 24))
                        mapCard
                            .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    recommendationCard
                        .glassEffect(.regular, in: .rect(cornerRadius: 24))
                    mapCard
                        .frame(height: 212)
                }

                Text("Your Fields")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 16)], spacing: 16) {
                    ForEach(sortedFields) { field in
                        Button {
                            onScan(field)
                        } label: {
                            FieldCard(
                                field: field,
                                activity: activity[field.id] ?? FieldActivity(),
                                status: geofence.status(for: field.region, location: location.lastLocation)
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Scan", systemImage: "camera.viewfinder") { onScan(field) }
                            Button("Rename", systemImage: "character.cursor.ibeam") { startRenaming(field) }
                            Button("Edit Field", systemImage: "pencil") { onEdit(field) }
                            Button("Directions", systemImage: "figure.walk") { PlaceNamer.openDirections(to: field.region) }
                            Divider()
                            Button("Delete Field", systemImage: "trash", role: .destructive) { pendingDeletion = field }
                        }
                        // Swipe a card for quick actions, outside a List (iOS 27).
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) { pendingDeletion = field }
                            Button("Rename", systemImage: "character.cursor.ibeam") { startRenaming(field) }
                                .tint(.gray)
                        }
                        .swipeActions(edge: .leading) {
                            Button("Directions", systemImage: "figure.walk") { PlaceNamer.openDirections(to: field.region) }
                                .tint(.blue)
                        }
                    }
                }
            }
            .padding()
        }
        .swipeActionsContainer()
        .refreshable { await refresh() }
        // A subtle multicolor wash behind the glass cards, like the Insights summary on iPad.
        .summaryGradientBackground()
        .navigationTitle("Fields")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Field", systemImage: "plus", action: onNewField)
            }
        }
        .alert("Rename Field", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $draftName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { saveRename() }
                .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("The new name shows everywhere, including past scans and widgets.")
        }
        .confirmationDialog(
            "Delete \(pendingDeletion?.name ?? "field")?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible
        ) {
            if let field = pendingDeletion {
                Button("Delete Field Only", role: .destructive) { delete(field, includingScans: false) }
                if !field.events.isEmpty {
                    Button("Delete Field and \(field.events.count) Scans", role: .destructive) { delete(field, includingScans: true) }
                }
            }
        } message: {
            Text("Keeping the scans leaves them in History without a field.")
        }
    }

    // MARK: - Recommendation

    @ViewBuilder
    private var recommendationCard: some View {
        let regions = fields.map(\.region)
        VStack(alignment: .leading, spacing: 14) {
            if location.isDenied {
                Text("Turn on location access to find the field you're standing in and verify scans.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Open Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.glass)
            } else if location.lastLocation == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding your location…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let inside = geofence.containingRegion(in: regions, location: location.lastLocation),
                      let field = fields.first(where: { $0.id == inside.id }) {
                VStack(alignment: .leading, spacing: 4) {
                    Label {
                        Text("You're in \(field.name)")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(Severity.clear.color)
                    }
                    .font(.title3.weight(.semibold))
                    Text("Your location is inside this field's boundary, so scans will be verified.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    onScan(field)
                } label: {
                    Label("Start Scanning", systemImage: "camera.viewfinder")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
            } else if let nearest = geofence.nearestRegion(in: regions, location: location.lastLocation),
                      let field = fields.first(where: { $0.id == nearest.id }) {
                let status = geofence.status(for: nearest, location: location.lastLocation)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nearest field: \(field.name)")
                        .font(.title3.weight(.semibold))
                    Text("\(status.distanceToEdge?.distanceText ?? "Some distance") from its boundary. Head there to log verified scans.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Button {
                        PlaceNamer.openDirections(to: nearest)
                    } label: {
                        Label("Directions", systemImage: "figure.walk")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        onScan(field)
                    } label: {
                        Label("Open Field", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.smooth, value: location.lastLocation == nil)
    }

    /// The fields map inset in a Liquid Glass bezel.
    private var mapCard: some View {
        FieldsOverviewMap(fields: fields, activity: activity)
            .clipShape(.rect(cornerRadius: 18))
            .padding(6)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    /// Pull to refresh: takes a fresh location fix, rechecks field boundaries and updates widgets.
    private func refresh() async {
        await location.refresh()
        await geofence.sync(fields.map(\.region))
        widgetSync?.update()
    }

    private func startRenaming(_ field: Field) {
        draftName = field.name
        renaming = field
    }

    private func saveRename() {
        guard let field = renaming else { return }
        let oldName = field.name
        if field.rename(to: draftName), field.name != oldName {
            try? modelContext.save()
            logger?.log(category: "field", "Renamed \(oldName) to \(field.name)")
        }
        renaming = nil
    }

    private func delete(_ field: Field, includingScans: Bool) {
        let name = field.name
        let id = field.id
        Task { try? await CSSearchableIndex.default().deleteAppEntities(identifiedBy: [id], ofType: FieldEntity.self) }
        if includingScans {
            for event in field.events { modelContext.delete(event) }
        }
        modelContext.delete(field)
        try? modelContext.save()
        logger?.log(category: "field", "Deleted \(name)\(includingScans ? " and its scans" : "")")
        pendingDeletion = nil
    }
}

// MARK: - Map

/// Latest scan state for one field.
struct FieldActivity {
    var latest: DetectionEvent?
    var severity: Severity?
}

struct FieldsOverviewMap: View {
    let fields: [Field]
    var activity: [UUID: FieldActivity] = [:]

    var body: some View {
        Map(initialPosition: .automatic) {
            UserAnnotation()
            ForEach(fields) { field in
                let center = CLLocationCoordinate2D(latitude: field.latitude, longitude: field.longitude)
                let tint = activity[field.id]?.severity?.color ?? Color.accentColor
                MapCircle(center: center, radius: field.radiusMeters)
                    .foregroundStyle(tint.opacity(0.2))
                    .stroke(tint, lineWidth: 2)
                Annotation(field.name, coordinate: center) {
                    Image(systemName: "leaf.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(6)
                        .background(tint, in: .circle)
                }
            }
        }
        .mapStyle(.hybrid)
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
    }
}

// MARK: - Field card

private struct FieldCard: View {
    let field: Field
    let activity: FieldActivity
    let status: GeofenceStatus

    var body: some View {
        let latest = activity.latest
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.name)
                        .font(.headline)
                    Text(field.locationName.isEmpty ? "Radius \(field.radiusMeters.distanceText)" : field.locationName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                // The recommendation card already says when you're inside, so only show distance otherwise.
                if status.presence != .inside, let distance = status.distanceMeters {
                    Label(distance.distanceText, systemImage: "location")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                if let latest {
                    Label {
                        Text(latest.timestamp, format: .relative(presentation: .named))
                    } icon: {
                        Image(systemName: "clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Last scanned \(latest.timestamp.formatted(.relative(presentation: .named)))")
                } else {
                    Label("Not scanned yet", systemImage: "camera.viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.card, in: .rect(cornerRadius: 20))
        .contentShape(.rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the scanner for this field")
    }
}
