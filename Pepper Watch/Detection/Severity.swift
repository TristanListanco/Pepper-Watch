//
//  Severity.swift
//  Pepper Watch
//
//  The "Actionable Output Panel" from the thesis (Table 3.4): translates raw class
//  counts into a plain-language status and treatment guidance.
//

import SwiftUI

nonisolated enum Severity: Int, CaseIterable, Comparable, Identifiable, Sendable {
    case clear, low, moderate, severe

    /// Share of infested leaves at which each level starts. These are app heuristics
    /// for field triage, not thresholds from the thesis.
    static let moderateThreshold = 0.25
    static let severeThreshold = 0.50

    init(aphidCount: Int, infestationRate: Double) {
        if aphidCount == 0 {
            self = .clear
        } else if infestationRate < Self.moderateThreshold {
            self = .low
        } else if infestationRate < Self.severeThreshold {
            self = .moderate
        } else {
            self = .severe
        }
    }

    var id: Int { rawValue }

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .clear: "Healthy"
        case .low: "Low"
        case .moderate: "Moderate"
        case .severe: "Severe"
        }
    }

    var rangeDescription: String {
        switch self {
        case .clear: "No infested leaves"
        case .low: "Under 25% of leaves infested"
        case .moderate: "25–50% of leaves infested"
        case .severe: "Over 50% of leaves infested"
        }
    }

    var symbol: String {
        switch self {
        case .clear: "checkmark.seal.fill"
        case .low: "exclamationmark.circle.fill"
        case .moderate: "exclamationmark.triangle.fill"
        case .severe: "xmark.octagon.fill"
        }
    }

    var headline: String {
        switch self {
        case .clear: "Leaves look healthy"
        case .low: "Early aphid activity"
        case .moderate: "Aphids are spreading"
        case .severe: "Heavy aphid infestation"
        }
    }

    var recommendations: [String] {
        switch self {
        case .clear:
            [
                "Keep scouting at least once a week.",
                "Check leaf undersides. Aphids gather there first.",
                "Watch for yellowing (chlorosis) and downward leaf curling.",
            ]
        case .low:
            [
                "Inspect the undersides of nearby leaves and plants.",
                "Remove heavily infested leaves or knock colonies off with a strong water spray.",
                "Mark this spot and re-scan in 2–3 days.",
            ]
        case .moderate:
            [
                "Spot-treat leaf undersides with insecticidal soap or neem oil, following the label.",
                "Protect natural enemies such as lady beetles and lacewings. Avoid broad-spectrum sprays.",
                "Go easy on nitrogen fertilizer, which favors aphid growth.",
                "Re-scan the area in 2–3 days to confirm the treatment worked.",
            ]
        case .severe:
            [
                "Treat this hotspot promptly to limit spread to neighboring rows.",
                "Check for honeydew and sooty mold, which block photosynthesis.",
                "Contact your municipal agriculturist or DA extension worker about approved controls.",
                "Remove badly damaged plants and watch for signs of virus transmission.",
            ]
        }
    }

    /// Yield-loss context from the thesis background (Kumari et al., 2025).
    var riskNote: String? {
        switch self {
        case .moderate: "Direct sap feeding can cut yields by 20–30%."
        case .severe: "Losses can exceed 80% when aphids spread viral or fungal disease."
        default: nil
        }
    }
}

extension Severity {
    /// Reserved status colors. Always shown with an icon and a label.
    @MainActor var color: Color {
        switch self {
        case .clear: Color(red: 0.047, green: 0.639, blue: 0.047)     // #0ca30c good
        case .low: Color(red: 0.980, green: 0.698, blue: 0.098)       // #fab219 warning
        case .moderate: Color(red: 0.925, green: 0.514, blue: 0.353)  // #ec835a serious
        case .severe: Color(red: 0.816, green: 0.231, blue: 0.231)    // #d03b3b critical
        }
    }
}
