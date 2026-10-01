//
//  DetectionTests.swift
//  PepperWatchTests
//
//  Severity levels, leaf counts, box overlap and the image-to-view mapping behind the overlays.
//

import CoreGraphics
import SwiftUI
import Testing
@testable import Pepper_Watch

@Suite("Severity")
struct SeverityTests {
    @Test("Thresholds from the thesis severity scale", arguments: [
        (0, 0.0, Severity.clear),
        (1, 0.10, .low),
        (3, 0.2499, .low),
        (5, 0.25, .moderate),
        (9, 0.4999, .moderate),
        (10, 0.50, .severe),
        (20, 1.0, .severe),
    ])
    func thresholds(aphidCount: Int, rate: Double, expected: Severity) {
        #expect(Severity(aphidCount: aphidCount, infestationRate: rate) == expected)
    }

    @Test func noAphidsIsClearWhateverTheRate() {
        #expect(Severity(aphidCount: 0, infestationRate: 0.9) == .clear)
    }

    @Test func levelsAreOrdered() {
        #expect(Severity.clear < .low)
        #expect(Severity.low < .moderate)
        #expect(Severity.moderate < .severe)
    }
}

@Suite("Detection summary")
struct DetectionSummaryTests {
    private func detection(_ leafClass: LeafClass) -> Detection {
        Detection(leafClass: leafClass, confidence: 0.9, rect: CGRect(x: 0, y: 0, width: 0.1, height: 0.1))
    }

    @Test func countsEachClass() {
        let summary = DetectionSummary([detection(.aphidInfested), detection(.healthy), detection(.healthy), detection(.aphidInfested)])
        #expect(summary.aphidCount == 2)
        #expect(summary.healthyCount == 2)
        #expect(summary.totalLeaves == 4)
        #expect(summary.infestationRate == 0.5)
        #expect(summary.severity == .severe)
    }

    @Test func noLeavesHasNoSeverity() {
        let summary = DetectionSummary([])
        #expect(summary.infestationRate == 0)
        #expect(summary.severity == nil)
    }
}

@Suite("Box overlap")
struct IntersectionOverUnionTests {
    @Test func identicalBoxesOverlapFully() {
        let box = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.4)
        #expect(abs(box.intersectionOverUnion(with: box) - 1) < 0.0001)
    }

    @Test func separateBoxesDoNotOverlap() {
        let left = CGRect(x: 0, y: 0, width: 0.2, height: 0.2)
        let right = CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)
        #expect(left.intersectionOverUnion(with: right) == 0)
    }

    @Test func touchingEdgesDoNotOverlap() {
        let left = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let right = CGRect(x: 0.5, y: 0, width: 0.5, height: 0.5)
        #expect(left.intersectionOverUnion(with: right) == 0)
    }

    @Test func halfShiftedBoxesOverlapByAThird() {
        // Two unit squares sharing half their area: 0.5 / (1 + 1 - 0.5).
        let first = CGRect(x: 0, y: 0, width: 1, height: 1)
        let second = CGRect(x: 0.5, y: 0, width: 1, height: 1)
        #expect(abs(first.intersectionOverUnion(with: second) - 1.0 / 3.0) < 0.0001)
    }
}

@Suite("Image to view mapping")
struct ImageTransformTests {
    @Test func fitLetterboxesAWideImage() {
        // A 2:1 image in a square view is scaled to the width and centered vertically.
        let transform = ImageTransform(imageSize: CGSize(width: 200, height: 100), viewSize: CGSize(width: 100, height: 100), contentMode: .fit)
        let rect = transform.rect(for: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(rect == CGRect(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func fillCropsAWideImage() {
        // Filling a square view overflows the sides equally.
        let transform = ImageTransform(imageSize: CGSize(width: 200, height: 100), viewSize: CGSize(width: 100, height: 100), contentMode: .fill)
        let rect = transform.rect(for: CGRect(x: 0, y: 0, width: 1, height: 1))
        #expect(rect == CGRect(x: -50, y: 0, width: 200, height: 100))
    }

    @Test func emptyImageMapsToTheView() {
        let transform = ImageTransform(imageSize: .zero, viewSize: CGSize(width: 80, height: 60), contentMode: .fit)
        #expect(transform.rect(for: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)) == CGRect(x: 40, y: 30, width: 40, height: 30))
    }
}
