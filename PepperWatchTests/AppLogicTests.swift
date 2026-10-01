//
//  AppLogicTests.swift
//  PepperWatchTests
//
//  Geofencing, deep links and navigation, pinned Insights metrics, auto-log de-duplication and
//  the resource plan.
//

import CoreGraphics
import CoreLocation
import Foundation
import Testing
@testable import Pepper_Watch

@Suite("Geofence")
struct GeofenceTests {
    private let region = FieldRegion(id: UUID(), name: "Field A", latitude: 8.61, longitude: 124.89, radiusMeters: 100)

    /// A fix a given distance north of the field center.
    private func location(metersNorth: Double, accuracy: Double = 5) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: region.latitude + metersNorth / 111_000, longitude: region.longitude),
            altitude: 0, horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: .now
        )
    }

    @Test func insideTheRadius() {
        let status = GeofenceService(logger: nil).status(for: region, location: location(metersNorth: 40))
        #expect(status.presence == .inside)
        #expect(status.distanceToEdge == 0)
    }

    @Test func outsideTheRadius() throws {
        let status = GeofenceService(logger: nil).status(for: region, location: location(metersNorth: 300))
        #expect(status.presence == .outside)
        let edge = try #require(status.distanceToEdge)
        #expect(abs(edge - 200) < 5)
    }

    @Test func jitterAtTheBoundaryCountsAsInside() {
        // 110 m out with 15 m accuracy is within the GPS tolerance.
        let status = GeofenceService(logger: nil).status(for: region, location: location(metersNorth: 110, accuracy: 15))
        #expect(status.presence == .inside)
    }

    @Test func coarseFixIsUnknown() {
        // Accuracy worse than the field itself can't place you in or out.
        let status = GeofenceService(logger: nil).status(for: region, location: location(metersNorth: 10, accuracy: 500))
        #expect(status.presence == .unknown)
    }

    @Test func closestContainingFieldWins() {
        let near = FieldRegion(id: UUID(), name: "Near", latitude: 8.61, longitude: 124.89, radiusMeters: 200)
        let far = FieldRegion(id: UUID(), name: "Far", latitude: 8.611, longitude: 124.89, radiusMeters: 400)
        let here = CLLocation(coordinate: CLLocationCoordinate2D(latitude: 8.61, longitude: 124.89), altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: .now)
        #expect(GeofenceService(logger: nil).containingRegion(in: [far, near], location: here)?.name == "Near")
    }
}

@Suite("Navigation")
struct NavigationTests {
    @Test func widgetLinksRoundTrip() throws {
        let id = UUID()
        let url = URL.pepperWatch("scan", fieldID: id.uuidString)
        #expect(url.scheme == "pepperwatch")
        #expect(url.host() == "scan")

        let navigator = AppNavigator()
        navigator.open(url)
        #expect(navigator.selectedTab == .scan)
        #expect(navigator.pendingScanFieldID == id)
    }

    @Test func allFieldsInsightsLinkClearsTheFilter() {
        let navigator = AppNavigator()
        navigator.open(.pepperWatch("insights", fieldID: WidgetSnapshot.allFieldsID))
        #expect(navigator.selectedTab == .insights)
        #expect(navigator.pendingInsightsFieldID == "")
    }

    @Test func unknownLinksAreIgnored() {
        let navigator = AppNavigator()
        let before = navigator.selectedTab
        navigator.open(URL(string: "pepperwatch://nowhere")!)
        #expect(navigator.selectedTab == before)
    }

    @Test func historyBadgeCountsUntilSeen() {
        let navigator = AppNavigator()
        navigator.noteNewScan()
        navigator.noteNewScan()
        #expect(navigator.unseenScans == 2)
        navigator.markHistorySeen()
        #expect(navigator.unseenScans == 0)
    }

    @Test func newFieldFromTheMenuBarOpensTheScanTab() {
        let navigator = AppNavigator()
        navigator.selectedTab = .history
        navigator.requestNewField()
        #expect(navigator.selectedTab == .scan)
        #expect(navigator.newFieldRequests == 1)
    }
}

@Suite("Pinned metrics")
struct PinnedMetricsTests {
    @Test func decodingSkipsUnknownAndRepeatedMetrics() {
        #expect(PinnedMetrics.decode("scans,bogus,scans,fields") == [.scans, .fields])
    }

    @Test func encodingRoundTrips() {
        let metrics: [InsightMetric] = [.accuracy, .infestation, .performance]
        #expect(PinnedMetrics.decode(PinnedMetrics.encode(metrics)) == metrics)
    }

    @Test func togglingPinsAndUnpins() {
        let pinned = PinnedMetrics.toggling(.confidence, in: "scans")
        #expect(PinnedMetrics.decode(pinned) == [.scans, .confidence])
        #expect(PinnedMetrics.decode(PinnedMetrics.toggling(.scans, in: pinned)) == [.confidence])
    }

    @Test func aboutTextSplitsIntoBalancedColumns() {
        let text = String(repeating: "aphids damage pepper leaves ", count: 20).trimmingCharacters(in: .whitespaces)
        let (leading, trailing) = InsightDetailView.balancedColumns(text)
        #expect(!leading.isEmpty && !trailing.isEmpty)
        #expect(abs(leading.count - trailing.count) < 40)
        #expect("\(leading) \(trailing)" == text)
    }
}

@Suite("Auto-log de-duplication")
struct AutoLogTests {
    private func leaf(_ leafClass: LeafClass, x: Double) -> Detection {
        Detection(leafClass: leafClass, confidence: 0.8, rect: CGRect(x: x, y: 0.2, width: 0.2, height: 0.3))
    }

    @Test func sameLeavesInPlaceAreADuplicate() {
        let saved = [leaf(.healthy, x: 0.1), leaf(.aphidInfested, x: 0.5)]
        let nudged = [leaf(.healthy, x: 0.11), leaf(.aphidInfested, x: 0.51)]
        #expect(ScanModel.showsSameLeaves(nudged, as: saved))
    }

    @Test func movedCameraIsANewView() {
        let saved = [leaf(.healthy, x: 0.1), leaf(.aphidInfested, x: 0.5)]
        let moved = [leaf(.healthy, x: 0.6), leaf(.aphidInfested, x: 0.0)]
        #expect(!ScanModel.showsSameLeaves(moved, as: saved))
    }

    @Test func differentLeafCountIsANewView() {
        let saved = [leaf(.healthy, x: 0.1)]
        #expect(!ScanModel.showsSameLeaves([leaf(.healthy, x: 0.1), leaf(.healthy, x: 0.5)], as: saved))
    }

    @Test func nothingSavedYetIsNeverADuplicate() {
        #expect(!ScanModel.showsSameLeaves([leaf(.healthy, x: 0.1)], as: []))
    }
}

@Suite("Resource plan")
struct ResourcePlanTests {
    /// The plan eases off when the device is warm or in Low Power Mode; these checks describe a
    /// cool device with Low Power Mode off.
    nonisolated static var isCoolAndOnFullPower: Bool {
        ThermalLevel(ProcessInfo.processInfo.thermalState) < .serious && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    @Test(.enabled(if: isCoolAndOnFullPower))
    func fullSpeedPipelinesWhenAllowed() {
        let plan = ResourcePlan.current(allowsPipelining: true, lensCheck: true)
        #expect(plan.mode == .full)
        #expect(plan.cameraFrameRate == nil)
        #expect(plan.framesInFlight == 2)
        #expect(plan.checksLens)
    }

    @Test(.enabled(if: isCoolAndOnFullPower))
    func oneFrameAtATimeWithoutPipelining() {
        #expect(ResourcePlan.current(allowsPipelining: false, lensCheck: false).framesInFlight == 1)
    }

    @Test func thermalLevelsAreOrdered() {
        #expect(ThermalLevel(.nominal) < ThermalLevel(.fair))
        #expect(ThermalLevel(.serious) < ThermalLevel(.critical))
    }
}
