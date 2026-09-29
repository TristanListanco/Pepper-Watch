//
//  LocationProvider.swift
//  Pepper Watch
//

import CoreLocation
import Observation

/// Streams the device location while scanning so detections can be mapped as field hotspots.
@Observable
final class LocationProvider {
    private(set) var lastLocation: CLLocation?
    private(set) var isDenied = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var serviceSession: CLServiceSession?

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
}
