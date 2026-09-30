//
//  FieldEditorView.swift
//  Pepper Watch
//

import CoreLocation
import CoreLocationUI
import MapKit
import SwiftData
import SwiftUI

/// Creates or edits a field: its name, place name and geofence boundary.
struct FieldEditorView: View {
    let field: Field?
    let onSave: (Field) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.systemLogger) private var logger
    @Environment(LocationProvider.self) private var location

    @State private var name = ""
    @State private var locationName = ""
    @State private var isLocationNameEdited = false
    @State private var center: CLLocationCoordinate2D?
    @State private var radius = 100.0
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var isResolvingPlace = false
    @State private var didLoad = false
    @FocusState private var focusedField: FocusTarget?

    private enum FocusTarget { case name, locationName }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && center != nil
    }

    /// Anything typed or moved that Cancel or a swipe down would lose. A new field's center and
    /// place fill in from your location, so only a typed name counts there.
    private var hasChanges: Bool {
        guard let field else { return !name.isEmpty }
        return name != field.name
            || locationName != field.locationName
            || radius != field.radiusMeters
            || center?.latitude != field.latitude
            || center?.longitude != field.longitude
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Field") {
                    TextField("Name, e.g. North Plot", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .locationName }
                    HStack {
                        TextField("Location name", text: $locationName)
                            .focused($focusedField, equals: .locationName)
                            .submitLabel(.done)
                            .onChange(of: locationName) { _, _ in
                                if focusedField == .locationName { isLocationNameEdited = true }
                            }
                        if isResolvingPlace {
                            ProgressView()
                        }
                    }
                }

                Section {
                    MapReader { proxy in
                        Map(position: $cameraPosition) {
                            UserAnnotation()
                            if let center {
                                MapCircle(center: center, radius: radius)
                                    .foregroundStyle(Color.accentColor.opacity(0.2))
                                    .stroke(Color.accentColor, lineWidth: 2)
                                Marker(name.isEmpty ? "Field" : name, systemImage: "leaf.fill", coordinate: center)
                                    .tint(Color.accentColor)
                            }
                        }
                        .mapStyle(.hybrid)
                        .mapControls { MapUserLocationButton() }
                        .onTapGesture { point in
                            if let coordinate = proxy.convert(point, from: .local) {
                                setCenter(coordinate, recenter: false)
                            }
                        }
                    }
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())

                    // One tap grants location access for this use, even without prior permission.
                    LocationButton(.currentLocation) {
                        Task {
                            await location.refresh(force: true)
                            if let coordinate = location.lastLocation?.coordinate {
                                setCenter(coordinate, recenter: true)
                            }
                        }
                    }
                    .symbolVariant(.fill)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.white)
                    .tint(Color.accentColor)
                    .clipShape(.capsule)
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Geofence radius", value: radius.distanceText)
                        Slider(value: $radius, in: 20...500, step: 5)
                            .accessibilityLabel("Geofence radius")
                            .accessibilityValue(radius.distanceText)
                    }
                } header: {
                    Text("Boundary")
                } footer: {
                    Text(center == nil
                         ? "Tap the map to place the field's center, or use your current location."
                         : "Tap the map to move the center. Scans are verified when you're inside this circle.")
                }
            }
            // Dragging the map or scrolling the form puts the keyboard away.
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(field == nil ? "New Field" : "Edit Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(field == nil ? "Create" : "Save", systemImage: "checkmark") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear(perform: load)
            .onChange(of: location.lastLocation == nil) {
                // The first fix after opening a new field becomes its default center.
                if field == nil, center == nil, let coordinate = location.lastLocation?.coordinate {
                    setCenter(coordinate, recenter: true)
                }
            }
        }
        // Swiping down only needs a guard when there's something to lose.
        .interactiveDismissDisabled(hasChanges)
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let field {
            name = field.name
            locationName = field.locationName
            isLocationNameEdited = true
            radius = field.radiusMeters
            setCenter(CLLocationCoordinate2D(latitude: field.latitude, longitude: field.longitude), recenter: true)
        } else {
            locationName = location.placeName ?? ""
            if let coordinate = location.lastLocation?.coordinate {
                setCenter(coordinate, recenter: true)
            }
            focusedField = .name
        }
    }

    private func setCenter(_ coordinate: CLLocationCoordinate2D, recenter: Bool) {
        center = coordinate
        if recenter {
            cameraPosition = .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: max(radius * 5, 300), longitudinalMeters: max(radius * 5, 300)))
        }
        guard !isLocationNameEdited else { return }
        isResolvingPlace = true
        Task {
            let place = await PlaceNamer.placeName(for: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            isResolvingPlace = false
            if let place, !isLocationNameEdited { locationName = place }
        }
    }

    private func save() {
        guard let center else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPlace = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved: Field
        if let field {
            field.rename(to: trimmedName)
            field.locationName = trimmedPlace
            field.latitude = center.latitude
            field.longitude = center.longitude
            field.radiusMeters = radius
            saved = field
            logger?.log(category: "field", "Updated \(trimmedName) (radius \(radius.distanceText))")
        } else {
            saved = Field(name: trimmedName, locationName: trimmedPlace, latitude: center.latitude, longitude: center.longitude, radiusMeters: radius)
            modelContext.insert(saved)
            logger?.log(category: "field", "Created \(trimmedName) at \(trimmedPlace.isEmpty ? "\(center.latitude.fixed(4)), \(center.longitude.fixed(4))" : trimmedPlace)")
        }
        try? modelContext.save()
        onSave(saved)
        dismiss()
    }
}
