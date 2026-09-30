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
}

nonisolated enum WatchWidgetKind {
    /// Configurable field status for the Smart Stack and watch faces.
    static let fieldStatus = "WatchFieldStatus"
    /// Appears in the Smart Stack on its own when you arrive at one of your fields.
    static let atField = "WatchAtField"
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
