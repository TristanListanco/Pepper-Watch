//
//  GeofenceService.swift
//  Pepper Watch
//
//  Verifies that scans happen inside the field they're logged to. Each field is a
//  CLMonitor circular condition; a precise live GPS fix takes priority because it
//  reacts faster than region events near the boundary.
//

import CoreLocation
import MapKit
import Observation

nonisolated enum GeofencePresence: Equatable, Sendable {
    case unknown
    case inside
    case outside
}

struct GeofenceStatus: Equatable {
    var presence: GeofencePresence
    /// Distance from the device to the field center, when a location fix is available.
    var distanceMeters: Double?
    var radiusMeters: Double

    /// How far outside the boundary the device is (0 when inside).
    var distanceToEdge: Double? {
        distanceMeters.map { max(0, $0 - radiusMeters) }
    }
}

@Observable
final class GeofenceService {
    private(set) var monitorStates: [UUID: GeofencePresence] = [:]

    @ObservationIgnored private var monitorTask: Task<CLMonitor, Never>?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var monitoredRegions: Set<FieldRegion> = []
    @ObservationIgnored private var regionNames: [UUID: String] = [:]
    @ObservationIgnored private let logger: SystemLogger?

    /// CLMonitor supports up to 20 conditions per app.
    static let maximumMonitoredFields = 20

    init(logger: SystemLogger?) {
        self.logger = logger
    }

    /// Keeps monitored conditions in step with the saved fields.
    func sync(_ regions: [FieldRegion]) async {
        let monitor = await ensureMonitor()
        let wanted = Set(regions.prefix(Self.maximumMonitoredFields))
        regionNames = Dictionary(uniqueKeysWithValues: wanted.map { ($0.id, $0.name) })

        for stale in monitoredRegions.subtracting(wanted) {
            await monitor.remove(stale.id.uuidString)
            monitorStates[stale.id] = nil
        }
        for region in wanted.subtracting(monitoredRegions) {
            let condition = CLMonitor.CircularGeographicCondition(
                center: CLLocationCoordinate2D(latitude: region.latitude, longitude: region.longitude),
                radius: region.radiusMeters
            )
            await monitor.add(condition, identifier: region.id.uuidString)
            if let record = await monitor.record(for: region.id.uuidString) {
                monitorStates[region.id] = Self.presence(record.lastEvent.state)
            }
        }
        monitoredRegions = wanted
    }

    func status(for region: FieldRegion, location: CLLocation?) -> GeofenceStatus {
        let center = CLLocation(latitude: region.latitude, longitude: region.longitude)
        let distance = location.map { $0.distance(from: center) }

        if let location, let distance, location.horizontalAccuracy >= 0,
           location.horizontalAccuracy <= max(region.radiusMeters, 50) {
            // Allow a little GPS jitter at the boundary.
            let tolerance = min(location.horizontalAccuracy, 20)
            return GeofenceStatus(
                presence: distance <= region.radiusMeters + tolerance ? .inside : .outside,
                distanceMeters: distance,
                radiusMeters: region.radiusMeters
            )
        }
        return GeofenceStatus(presence: monitorStates[region.id] ?? .unknown, distanceMeters: distance, radiusMeters: region.radiusMeters)
    }

    /// The field the device is currently inside, if any (closest center wins when geofences overlap).
    func containingRegion(in regions: [FieldRegion], location: CLLocation?) -> FieldRegion? {
        regions
            .map { ($0, status(for: $0, location: location)) }
            .filter { $0.1.presence == .inside }
            .min { ($0.1.distanceMeters ?? .infinity) < ($1.1.distanceMeters ?? .infinity) }?
            .0
    }

    func nearestRegion(in regions: [FieldRegion], location: CLLocation?) -> FieldRegion? {
        guard let location else { return nil }
        return regions.min {
            location.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < location.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
    }

    // MARK: - Monitor

    private func ensureMonitor() async -> CLMonitor {
        if let monitorTask { return await monitorTask.value }
        let task = Task { await CLMonitor("PepperWatchFields") }
        monitorTask = task
        let monitor = await task.value
        listen(to: monitor)
        return monitor
    }

    private func listen(to monitor: CLMonitor) {
        eventsTask = Task { [weak self] in
            do {
                for try await event in await monitor.events {
                    guard let self, let id = UUID(uuidString: event.identifier) else { continue }
                    let presence = Self.presence(event.state)
                    let previous = self.monitorStates[id]
                    self.monitorStates[id] = presence
                    if let previous, previous != .unknown, presence != .unknown, previous != presence {
                        let name = self.regionNames[id] ?? "field"
                        self.logger?.log(category: "geofence", presence == .inside ? "Entered \(name)" : "Left \(name)")
                    }
                }
            } catch {
                self?.logger?.log(.warning, category: "geofence", "Geofence monitoring stopped: \(error.localizedDescription)")
            }
        }
    }

    private static func presence(_ state: CLMonitor.Event.State) -> GeofencePresence {
        switch state {
        case .satisfied: .inside
        case .unsatisfied: .outside
        default: .unknown
        }
    }
}

// MARK: - Places

enum PlaceNamer {
    /// A short place description such as "Claveria, Misamis Oriental".
    static func placeName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let item = try? await request.mapItems.first
        else { return nil }
        return item.addressRepresentations?.cityWithContext ?? item.address?.shortAddress ?? item.name
    }

    /// Opens Apple Maps with walking directions to a field's center.
    static func openDirections(to region: FieldRegion) {
        let item = MKMapItem(location: CLLocation(latitude: region.latitude, longitude: region.longitude), address: nil)
        item.name = region.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}

extension Double {
    /// "85 m" / "1.2 km"
    var distanceText: String {
        Measurement(value: self, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }
}
