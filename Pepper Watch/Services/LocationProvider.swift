//
//  LocationProvider.swift
//  Pepper Watch
//

import CoreLocation
import Observation

/// Streams the device location while the Scan tab is active: it drives field recommendations,
/// geofence checks and geotagged detections.
///
/// Kept light on power and on the main thread: Core Location pauses the stream while the device
/// is stationary, and a new position is only published when it matters (a real move, a clearly
/// better fix, or a while since the last one), so views don't re-render for GPS jitter.
@Observable
final class LocationProvider {
    private(set) var lastLocation: CLLocation?
    /// Reverse-geocoded name of the current position, refreshed after moving a meaningful distance.
    private(set) var placeName: String?
    private(set) var isDenied = false
    /// Precise Location is off, so fixes are too coarse to verify a scan is inside a field.
    private(set) var isAccuracyLimited = false

    /// Updates received and published since launch, for the developer diagnostics.
    @ObservationIgnored private(set) var updatesReceived = 0
    @ObservationIgnored private(set) var updatesPublished = 0

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    /// Asks for temporary precise location while scanning when Precise Location is off (iOS 14's
    /// temporary full accuracy, requested through a service session).
    @ObservationIgnored private var preciseSession: CLServiceSession?
    private static let fullAccuracyPurpose = "FieldVerification"
    @ObservationIgnored private var lastGeocodedLocation: CLLocation?

    /// Publish thresholds: field boundaries are tens of meters, so smaller changes are noise.
    private static let minimumMove: CLLocationDistance = 5
    private static let minimumAccuracyGain: CLLocationAccuracy = 5
    private static let maximumQuietInterval: TimeInterval = 30

    var isRunning: Bool { updatesTask != nil }

    func start() {
        guard updatesTask == nil else { return }
        serviceSession = CLServiceSession(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            do {
                // The general-purpose configuration: Core Location picks the radios and backs off
                // while stationary. Navigation configurations would keep GPS at full power.
                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    guard let self else { return }
                    self.handle(update)
                }
            } catch {
                // Updates end on cancellation; the last known location stays usable.
            }
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        serviceSession?.invalidate()
        serviceSession = nil
        preciseSession?.invalidate()
        preciseSession = nil
    }

    /// Shows the system prompt for precise location until the app goes to the background, so
    /// scans can be checked against a field's boundary even with Precise Location off.
    func requestPreciseLocation() {
        preciseSession?.invalidate()
        preciseSession = CLServiceSession(authorization: .whenInUse, fullAccuracyPurposeKey: Self.fullAccuracyPurpose)
    }

    private func handle(_ update: CLLocationUpdate) {
        updatesReceived += 1
        // Only write observed properties when they change, so views don't re-render needlessly.
        let denied = update.authorizationDenied || update.authorizationDeniedGlobally
        if denied != isDenied { isDenied = denied }
        if update.accuracyLimited != isAccuracyLimited { isAccuracyLimited = update.accuracyLimited }

        // While stationary Core Location repeats the last fix; nothing new to publish.
        guard !update.stationary, let location = update.location, location.horizontalAccuracy >= 0,
              shouldPublish(location)
        else { return }
        updatesPublished += 1
        lastLocation = location
        refreshPlaceName(for: location)
    }

    private func shouldPublish(_ location: CLLocation) -> Bool {
        guard let last = lastLocation else { return true }
        if location.distance(from: last) >= Self.minimumMove { return true }
        if last.horizontalAccuracy - location.horizontalAccuracy >= Self.minimumAccuracyGain { return true }
        return location.timestamp.timeIntervalSince(last.timestamp) >= Self.maximumQuietInterval
    }

    /// Pull to refresh: waits briefly for a fresh fix, then looks up the place name again.
    /// `force` tries even after a denial, for a location button that just granted one-time access.
    func refresh(timeout: Duration = .seconds(4), force: Bool = false) async {
        guard force || !isDenied else { return }
        if let fix = await Self.freshLocation(timeout: timeout) {
            lastLocation = fix
        }
        guard let location = lastLocation else { return }
        lastGeocodedLocation = location
        if let name = await PlaceNamer.placeName(for: location) {
            placeName = name
        }
    }

    /// The first fix from a new update stream that's no more than a few seconds old, or `nil` on timeout.
    @concurrent private static func freshLocation(timeout: Duration) async -> CLLocation? {
        let requested = Date.now
        return await withTaskGroup(of: CLLocation?.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if let location = update.location, location.timestamp.timeIntervalSince(requested) > -5 {
                            return location
                        }
                    }
                } catch {}
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func refreshPlaceName(for location: CLLocation) {
        if let lastGeocodedLocation, location.distance(from: lastGeocodedLocation) < 150 { return }
        lastGeocodedLocation = location
        Task { [weak self] in
            if let name = await PlaceNamer.placeName(for: location) {
                self?.placeName = name
            }
        }
    }
}
