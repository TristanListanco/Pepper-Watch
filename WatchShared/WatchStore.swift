//
//  WatchStore.swift
//  Pepper Watch (shared by the Apple Watch app and its widgets)
//
//  The latest iPhone payload and the briefs made on the watch, kept in the App Group
//  so Smart Stack widgets show the same numbers as the app.
//

import Foundation

/// A glanceable Apple Intelligence brief made on the watch for one scope.
nonisolated struct WatchBrief: Codable, Sendable, Equatable {
    var headline: String
    var action: String
    /// The facts the brief was made from; a brief is shown only while they still match.
    var facts: String
    var generatedAt: Date
}

nonisolated enum WatchStore {
    private static let payloadKey = "watch.payload"
    private static let briefsKey = "watch.briefs"

    static var payload: WatchPayload? {
        SharedContainer.defaults.data(forKey: payloadKey).flatMap(WatchPayload.decoded(from:))
    }

    static func savePayload(_ data: Data) {
        SharedContainer.defaults.set(data, forKey: payloadKey)
    }

    /// The saved brief for `scope`, when it was made from the current numbers.
    static func brief(for scope: String, facts: String) -> WatchBrief? {
        guard let brief = briefs[scope], brief.facts == facts else { return nil }
        return brief
    }

    static func saveBrief(_ brief: WatchBrief, for scope: String) {
        var all = briefs
        all[scope] = brief
        if let data = try? JSONEncoder().encode(all) {
            SharedContainer.defaults.set(data, forKey: briefsKey)
        }
    }

    private static var briefs: [String: WatchBrief] {
        guard let data = SharedContainer.defaults.data(forKey: briefsKey),
              let briefs = try? JSONDecoder().decode([String: WatchBrief].self, from: data)
        else { return [:] }
        return briefs
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
