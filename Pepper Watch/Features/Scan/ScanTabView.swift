//
//  ScanTabView.swift
//  Pepper Watch
//
//  Scan tab flow: onboarding (first field) → Fields home → full-screen scanner.
//

import AppIntents
import CoreSpotlight
import SwiftData
import SwiftUI

enum FieldEditorRoute: Identifiable {
    case new
    case edit(Field)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let field): field.id.uuidString
        }
    }

    var field: Field? {
        if case .edit(let field) = self { field } else { nil }
    }
}

struct ScanTabView: View {
    let isSelected: Bool

    @Environment(LocationProvider.self) private var location
    @Environment(GeofenceService.self) private var geofence
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Field.createdAt) private var fields: [Field]
    @State private var path: [Field] = []
    @State private var editorRoute: FieldEditorRoute?

    private var isActive: Bool { isSelected && scenePhase == .active }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if fields.isEmpty {
                    FieldOnboardingView { editorRoute = .new }
                } else {
                    FieldsHomeView(
                        fields: fields,
                        onScan: { path.append($0) },
                        onNewField: { editorRoute = .new },
                        onEdit: { editorRoute = .edit($0) }
                    )
                }
            }
            .navigationDestination(for: Field.self) { field in
                ScanView(field: field)
            }
        }
        .sheet(item: $editorRoute) { route in
            FieldEditorView(field: route.field) { saved in
                // A newly created field goes straight to scanning.
                if route.field == nil { path = [saved] }
            }
        }
        .task(id: isActive) {
            if isActive { location.start() } else { location.stop() }
        }
        .task(id: fields.map(\.region)) {
            await geofence.sync(fields.map(\.region))
            // Let Siri, Shortcuts and Spotlight know about field names.
            PepperWatchShortcuts.updateAppShortcutParameters()
            try? await CSSearchableIndex.default().indexAppEntities(fields.map { FieldEntity($0) })
        }
        .onChange(of: AppNavigator.shared.pendingScanFieldID, initial: true) { _, fieldID in
            // "Start scanning" from Siri or a widget opens that field's scanner.
            guard let fieldID, let field = fields.first(where: { $0.id == fieldID }) else { return }
            path = [field]
            AppNavigator.shared.pendingScanFieldID = nil
        }
    }
}

// MARK: - Onboarding

struct FieldOnboardingView: View {
    let onCreateField: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                VStack(spacing: 16) {
                    Image(systemName: "leaf.circle.fill")
                        .font(.system(size: 88))
                        .foregroundStyle(.tint)
                        .symbolRenderingMode(.hierarchical)
                    Text("Set Up Your First Field")
                        .font(.largeTitle.weight(.bold))
                        .multilineTextAlignment(.center)
                    Text("Pepper Watch links every scan to a field so it can check where you are and track aphid damage over time.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)

                VStack(alignment: .leading, spacing: 22) {
                    OnboardingRow(
                        symbol: "mappin.and.ellipse",
                        title: "Name and place it",
                        detail: "Give the field a name. Its location is filled in from where you're standing."
                    )
                    OnboardingRow(
                        symbol: "location.circle",
                        title: "Geofenced scans",
                        detail: "A boundary around the field confirms each scan really happened there."
                    )
                    OnboardingRow(
                        symbol: "camera.viewfinder",
                        title: "Scan on-device",
                        detail: "Detect aphid-infested and healthy leaves offline. Nothing leaves your phone."
                    )
                }
                .padding(.horizontal, 8)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                Button(action: onCreateField) {
                    Text("Create Field")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)

                Button("Explore with Demo Fields") {
                    withAnimation { DemoDataGenerator.generate(in: modelContext) }
                }
                .font(.subheadline)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            .frame(maxWidth: 560)
        }
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OnboardingRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Geofence badge

/// Shows whether the device is inside a field's boundary.
struct GeofenceBadge: View {
    let status: GeofenceStatus?
    var fieldName: String?

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.22), in: .capsule)
            .overlay(Capsule().strokeBorder(tint.opacity(0.55), lineWidth: 1))
            .accessibilityLabel(accessibilityText)
    }

    private var title: String {
        switch status?.presence {
        case .inside: "Inside field"
        case .outside:
            status?.distanceToEdge.map { "\($0.distanceText) outside" } ?? "Outside field"
        case .unknown, nil: "Locating…"
        }
    }

    private var symbol: String {
        switch status?.presence {
        case .inside: "checkmark.seal.fill"
        case .outside: "location.slash.fill"
        case .unknown, nil: "location.magnifyingglass"
        }
    }

    private var tint: Color {
        switch status?.presence {
        case .inside: Severity.clear.color
        case .outside: Severity.low.color
        case .unknown, nil: .secondary
        }
    }

    private var accessibilityText: String {
        let name = fieldName ?? "the field"
        switch status?.presence {
        case .inside: return "Location verified inside \(name)"
        case .outside: return "Outside \(name)" + (status?.distanceToEdge.map { " by \($0.distanceText)" } ?? "")
        case .unknown, nil: return "Checking location"
        }
    }
}
