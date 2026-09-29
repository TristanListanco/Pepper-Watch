//
//  WatchPayload.swift
//  Pepper Watch (shared with the Apple Watch app)
//
//  What the iPhone sends to the paired Apple Watch over WatchConnectivity: the same
//  30-day daily counts the widgets use, plus a highlights summary for each scope.
//

import Foundation

nonisolated struct WatchPayload: Codable, Sendable {
    /// A short summary for one scope, generated with Apple Intelligence on the iPhone or rule-based.
    nonisolated struct Highlight: Codable, Sendable, Equatable {
        var headline: String?
        var observations: [String]
        var recommendation: String?
        var isGenerated: Bool
        var generatedAt: Date?
    }

    /// Application context key holding the encoded payload.
    static let contextKey = "payload"
    /// Message key the watch sends to ask for the latest payload.
    static let requestKey = "request"

    var snapshot: WidgetSnapshot
    /// Keyed by `FieldStatus.id`: a field UUID or `WidgetSnapshot.allFieldsID`.
    var highlights: [String: Highlight]

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> WatchPayload? {
        try? JSONDecoder().decode(WatchPayload.self, from: data)
    }
}
