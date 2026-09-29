//
//  FieldEntity.swift
//  Pepper Watch
//
//  Exposes fields to Siri, Shortcuts, Spotlight and Apple Intelligence.
//

import AppIntents
import CoreSpotlight
import SwiftData

struct FieldEntity: IndexedEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Field",
        numericFormat: "\(placeholder: .int) fields"
    )
    static let defaultQuery = FieldEntityQuery()

    let id: UUID

    @Property(title: "Name")
    var name: String

    @Property(title: "Location")
    var locationName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(locationName)",
            image: DisplayRepresentation.Image(systemName: "leaf.fill")
        )
    }

    init(id: UUID, name: String, locationName: String) {
        self.id = id
        self.name = name
        self.locationName = locationName
    }
}

extension FieldEntity {
    init(_ field: Field) {
        self.init(id: field.id, name: field.name, locationName: field.locationName)
    }
}

nonisolated struct FieldEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [FieldEntity] {
        try fields().filter { identifiers.contains($0.id) }.map { FieldEntity($0) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [FieldEntity] {
        try fields()
            .filter { $0.name.localizedCaseInsensitiveContains(string) || $0.locationName.localizedCaseInsensitiveContains(string) }
            .map { FieldEntity($0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [FieldEntity] {
        try fields().map { FieldEntity($0) }
    }

    @MainActor
    private func fields() throws -> [Field] {
        try AppDataStore.container.mainContext.fetch(FetchDescriptor<Field>(sortBy: [SortDescriptor(\.name)]))
    }
}
