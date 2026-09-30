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

    /// Detections the user confirmed or rejected in History, for the aphid-infested class
    /// (thesis Section 4.10): TP, FP, TN and FN counts.
    nonisolated struct Validation: Codable, Sendable, Equatable {
        var truePositives: Int
        var falsePositives: Int
        var trueNegatives: Int
        var falseNegatives: Int

        var total: Int { truePositives + falsePositives + trueNegatives + falseNegatives }
        var precision: Double? { ratio(truePositives, truePositives + falsePositives) }
        var recall: Double? { ratio(truePositives, truePositives + falseNegatives) }
        var accuracy: Double? { ratio(truePositives + trueNegatives, total) }
        var f1: Double? {
            guard let precision, let recall, precision + recall > 0 else { return nil }
            return 2 * precision * recall / (precision + recall)
        }

        private func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
            denominator == 0 ? nil : Double(numerator) / Double(denominator)
        }
    }

    /// The time ranges the watch's range button steps through.
    nonisolated enum TrendRange: String, Codable, CaseIterable, Sendable {
        case day = "D", week = "W", month = "M", sixMonths = "6M", year = "Y"

        /// Bucket size and count: 24 hours, 7 or 30 days, 26 weeks, 12 months.
        var bucket: (component: Calendar.Component, count: Int) {
            switch self {
            case .day: (.hour, 24)
            case .week: (.day, 7)
            case .month: (.day, 30)
            case .sixMonths: (.weekOfYear, 26)
            case .year: (.month, 12)
            }
        }

        var next: TrendRange {
            let all = Self.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    /// Leaf and scan totals for one bucket of a trend.
    nonisolated struct TrendBucket: Codable, Sendable, Identifiable, Equatable {
        var start: Date
        var aphid: Int
        var total: Int
        var scans: Int

        var id: Date { start }
        var rate: Double? { total == 0 ? nil : Double(aphid) / Double(total) }

        // Short keys keep the payload small; it's sent often and has a size budget.
        private enum CodingKeys: String, CodingKey {
            case start = "s", aphid = "a", total = "t", scans = "n"
        }
    }

    /// One range for one scope: its buckets, oldest first, and the totals for the period before it.
    nonisolated struct Trend: Codable, Sendable, Equatable {
        var buckets: [TrendBucket]
        var previous: TrendBucket
    }

    /// Application context key holding the encoded payload.
    static let contextKey = "payload"
    /// Message key the watch sends to ask for the latest payload.
    static let requestKey = "request"

    var snapshot: WidgetSnapshot
    /// Keyed by `FieldStatus.id`: a field UUID or `WidgetSnapshot.allFieldsID`.
    var highlights: [String: Highlight]
    /// All verified detections per scope, keyed like `highlights`. Optional so older payloads still decode.
    var validation: [String: Validation]? = nil
    /// Per scope, then per `TrendRange.rawValue`.
    var trends: [String: [String: Trend]]? = nil

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decoded(from data: Data) -> WatchPayload? {
        try? JSONDecoder().decode(WatchPayload.self, from: data)
    }
}
