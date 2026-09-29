//
//  LocationProvider.swift
//  Pepper Watch
//

import CoreLocation
import Observation

/// Streams the device location while the Scan tab is active: it drives field recommendations,
/// geofence checks and geotagged detections.
@Observable
final class LocationProvider {
    private(set) var lastLocation: CLLocation?
    /// Reverse-geocoded name of the current position, refreshed after moving a meaningful distance.
    private(set) var placeName: String?
    private(set) var isDenied = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var serviceSession: CLServiceSession?
    @ObservationIgnored private var lastGeocodedLocation: CLLocation?

    var isRunning: Bool { updatesTask != nil }

    func start() {
        guard updatesTask == nil else { return }
        serviceSession = CLServiceSession(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    guard let self else { return }
                    self.isDenied = update.authorizationDenied || update.authorizationDeniedGlobally
                    if let location = update.location {
                        self.lastLocation = location
                        self.refreshPlaceName(for: location)
                    }
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
    }

    /// Pull to refresh: waits briefly for a fresh fix, then looks up the place name again.
    func refresh(timeout: Duration = .seconds(4)) async {
        guard !isDenied else { return }
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
