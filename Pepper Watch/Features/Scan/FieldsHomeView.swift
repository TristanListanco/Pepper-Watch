//
//  FieldsHomeView.swift
//  Pepper Watch
//
//  Scan tab home: detects where the device is and recommends the field to scan.
//

import CoreLocation
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
    @Environment(\.openURL) private var openURL
    @State private var pendingDeletion: Field?

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
                recommendationCard
                FieldsOverviewMap(fields: fields)
                    .frame(height: 200)
                    .clipShape(.rect(cornerRadius: 24))

                Text("Your Fields")
                    .font(.title3.weight(.semibold))
                    .padding(.top, 4)

                ForEach(sortedFields) { field in
                    Button {
                        onScan(field)
                    } label: {
                        FieldCard(field: field, status: geofence.status(for: field.region, location: location.lastLocation))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Scan", systemImage: "camera.viewfinder") { onScan(field) }
                        Button("Edit Field", systemImage: "pencil") { onEdit(field) }
                        Button("Directions", systemImage: "figure.walk") { PlaceNamer.openDirections(to: field.region) }
                        Divider()
                        Button("Delete Field", systemImage: "trash", role: .destructive) { pendingDeletion = field }
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Fields")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Field", systemImage: "plus", action: onNewField)
            }
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
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Current Location")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(locationTitle)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                if let accuracy = location.lastLocation?.horizontalAccuracy, accuracy >= 0 {
                    Text("±\(accuracy.distanceText)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

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
        .background(.card, in: .rect(cornerRadius: 24))
        .animation(.smooth, value: location.lastLocation == nil)
    }

    private var locationTitle: String {
        if let placeName = location.placeName { return placeName }
        if let coordinate = location.lastLocation?.coordinate {
            return "\(coordinate.latitude.fixed(4)), \(coordinate.longitude.fixed(4))"
        }
        return location.isDenied ? "Location unavailable" : "Locating…"
    }

    private func delete(_ field: Field, includingScans: Bool) {
        let name = field.name
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

struct FieldsOverviewMap: View {
    let fields: [Field]

    var body: some View {
        Map(initialPosition: .automatic) {
            UserAnnotation()
            ForEach(fields) { field in
                let center = CLLocationCoordinate2D(latitude: field.latitude, longitude: field.longitude)
                let tint = field.latestEvent?.severity?.color ?? Color.accentColor
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
    let status: GeofenceStatus

    var body: some View {
        let latest = field.latestEvent
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
                if status.presence == .inside {
                    GeofenceBadge(status: status, fieldName: field.name)
                } else if let distance = status.distanceMeters {
                    Label(distance.distanceText, systemImage: "location")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                if let latest {
                    SeverityBadge(severity: latest.severity, compact: true)
                    Text("Last scan \(latest.timestamp, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Not scanned yet", systemImage: "camera.viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(field.events.count) scans")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
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
