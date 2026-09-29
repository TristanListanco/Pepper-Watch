//
//  Pepper_WatchApp.swift
//  Pepper Watch
//
//  Created by Tristan Listanco on 9/29/26.
//

import SwiftData
import SwiftUI

@main
struct Pepper_WatchApp: App {
    private let container: ModelContainer
    private let logger: SystemLogger
    @State private var engine: DetectionEngine
    @State private var scanner: ScanModel
    @State private var location: LocationProvider
    @State private var geofence: GeofenceService
    @State private var deviceMonitor = DeviceMonitor()

    init() {
        AppSettings.registerDefaults()

        let schema = AppSchema.schema
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema)
        } catch {
            // Keep the app usable for a demo even if the on-disk store can't open.
            container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        }
        self.container = container

        #if DEBUG
        // `-PWSeedDemo YES` fills an empty store with demo data for screenshots.
        if UserDefaults.standard.bool(forKey: "PWSeedDemo"),
           (try? container.mainContext.fetchCount(FetchDescriptor<DetectionEvent>())) == 0 {
            DemoDataGenerator.generate(in: container.mainContext)
        }
        #endif

        let logger = SystemLogger(context: container.mainContext)
        let engine = DetectionEngine(logger: logger)
        let location = LocationProvider()
        let geofence = GeofenceService(logger: logger)
        self.logger = logger
        _engine = State(initialValue: engine)
        _location = State(initialValue: location)
        _geofence = State(initialValue: geofence)
        _scanner = State(initialValue: ScanModel(
            context: container.mainContext, engine: engine, logger: logger, location: location, geofence: geofence
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(engine)
                .environment(scanner)
                .environment(location)
                .environment(geofence)
                .environment(deviceMonitor)
                .environment(\.systemLogger, logger)
                .task { await engine.configure(AppSettings.detectorConfiguration) }
        }
        .modelContainer(container)
    }
}
