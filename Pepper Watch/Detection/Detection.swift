//
//  Detection.swift
//  Pepper Watch
//

import CoreGraphics
import Foundation

/// One bounding box produced by the detector.
nonisolated struct Detection: Identifiable, Hashable, Sendable {
    var id = UUID()
    var leafClass: LeafClass
    var confidence: Double
    /// Normalized to the upright image, origin at the top-left.
    var rect: CGRect
}

/// Counts derived from a set of detections. Used by the live HUD, saved events and charts.
nonisolated struct DetectionSummary: Equatable, Sendable {
    var aphidCount = 0
    var healthyCount = 0

    init(aphidCount: Int = 0, healthyCount: Int = 0) {
        self.aphidCount = aphidCount
        self.healthyCount = healthyCount
    }

    init(_ detections: [Detection]) {
        for detection in detections {
            switch detection.leafClass {
            case .aphidInfested: aphidCount += 1
            case .healthy: healthyCount += 1
            }
        }
    }

    var totalLeaves: Int { aphidCount + healthyCount }

    /// Share of detected leaves that are aphid-infested (0...1).
    var infestationRate: Double {
        totalLeaves == 0 ? 0 : Double(aphidCount) / Double(totalLeaves)
    }

    /// `nil` when no leaves are in view.
    var severity: Severity? {
        totalLeaves == 0 ? nil : Severity(aphidCount: aphidCount, infestationRate: infestationRate)
    }
}

nonisolated extension CGRect {
    func intersectionOverUnion(with other: CGRect) -> Double {
        let intersection = self.intersection(other)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = width * height + other.width * other.height - intersectionArea
        return unionArea > 0 ? Double(intersectionArea / unionArea) : 0
    }
}
