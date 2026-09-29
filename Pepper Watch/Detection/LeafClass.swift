//
//  LeafClass.swift
//  Pepper Watch
//

import SwiftUI

/// The two classes the YOLO model was trained on (`names` in the model metadata).
nonisolated enum LeafClass: String, CaseIterable, Codable, Identifiable, Sendable {
    case aphidInfested = "aphid_infested"
    case healthy = "healthy"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aphidInfested: "Aphid-infested"
        case .healthy: "Healthy"
        }
    }

    var shortName: String {
        switch self {
        case .aphidInfested: "Aphid"
        case .healthy: "Healthy"
        }
    }

    /// Icons pair with color so class identity never relies on color alone.
    var symbol: String {
        switch self {
        case .aphidInfested: "ant.fill"
        case .healthy: "leaf.fill"
        }
    }
}

extension LeafClass {
    @MainActor var color: Color {
        switch self {
        case .aphidInfested: Color("Aphid")
        case .healthy: Color("Healthy")
        }
    }
}
