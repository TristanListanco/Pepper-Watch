//
//  WatchStore.swift
//  Pepper Watch (shared by the Apple Watch app and its widgets)
//
//  The latest iPhone payload, kept in the App Group so Smart Stack widgets show the same
//  numbers as the app.
//

import Foundation

nonisolated enum WatchStore {
    private static let payloadKey = "watch.payload"

    static var payload: WatchPayload? {
        SharedContainer.defaults.data(forKey: payloadKey).flatMap(WatchPayload.decoded(from:))
    }

    static func savePayload(_ data: Data) {
        SharedContainer.defaults.set(data, forKey: payloadKey)
    }

    // MARK: Field order

    /// Field IDs in the order set on the watch, comma-separated; shared with the widgets.
    static let fieldOrderKey = "watch.fieldOrder"

    /// The synced fields in the watch's order; fields it hasn't placed yet follow in the iPhone's order.
    static func ordered(_ fields: [WidgetSnapshot.FieldStatus], order: String? = nil) -> [WidgetSnapshot.FieldStatus] {
        let ids = (order ?? SharedContainer.defaults.string(forKey: fieldOrderKey) ?? "").split(separator: ",").map(String.init)
        let rank = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return fields.enumerated()
            .sorted { (rank[$0.element.id] ?? ids.count + $0.offset) < (rank[$1.element.id] ?? ids.count + $1.offset) }
            .map(\.element)
    }

    /// Moves the dragged fields to where they were dropped and returns the new order.
    static func reordering(_ fields: [WidgetSnapshot.FieldStatus], sources: [String], before destination: String?) -> String {
        var ids = fields.map(\.id)
        let moving = ids.filter { sources.contains($0) }
        ids.removeAll { sources.contains($0) }
        let index = destination.flatMap { id in ids.firstIndex(of: id) } ?? ids.endIndex
        ids.insert(contentsOf: moving, at: index)
        return ids.joined(separator: ",")
    }
}

nonisolated enum WatchWidgetKind {
    /// Configurable field status for the Smart Stack and watch faces.
    static let fieldStatus = "WatchFieldStatus"
    /// Appears in the Smart Stack on its own when you arrive at one of your fields.
    static let atField = "WatchAtField"
    /// Control Center, Smart Stack and Action button control for one field (watchOS 26).
    static let fieldControl = "WatchFieldControl"
    /// Up to three fields side by side in one Smart Stack card.
    static let yourFields = "WatchYourFields"
}

extension URL {
    /// `pepperwatch://field?id=<id>`: opens the watch app on that field's insights.
    static func watchField(_ id: String) -> URL {
        var components = URLComponents()
        components.scheme = "pepperwatch"
        components.host = "field"
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url!
    }
}
