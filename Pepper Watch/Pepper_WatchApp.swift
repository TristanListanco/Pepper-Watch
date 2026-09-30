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
    init() {
        AppSettings.registerDefaults()
        PepperWatchTips.configure()
        // Activate WatchConnectivity at launch, including background launches the watch triggers.
        AppServices.shared.watchSync.start()
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

/// Long-lived services, created once when the app starts.
final class AppServices {
    static let shared = AppServices()

    let container: ModelContainer
    let logger: SystemLogger
    let engine: DetectionEngine
    let location = LocationProvider()
    let geofence: GeofenceService
    let scanner: ScanModel
    let deviceMonitor = DeviceMonitor()
    let widgetSync: WidgetSync
    let watchSync: WatchSync

    private init() {
        container = AppDataStore.container
        let context = container.mainContext
        DetectionEvent.backfillDayKeys(in: context)

        #if DEBUG
        // `-PWSeedDemo YES` fills an empty store with demo data for screenshots.
        if UserDefaults.standard.bool(forKey: "PWSeedDemo"),
           (try? context.fetchCount(FetchDescriptor<DetectionEvent>())) == 0 {
            DemoDataGenerator.generate(in: context)
        }
        #endif

        logger = SystemLogger(context: context)
        engine = DetectionEngine(logger: logger)
        geofence = GeofenceService(logger: logger)
        scanner = ScanModel(context: context, engine: engine, logger: logger, location: location, geofence: geofence)
        watchSync = WatchSync(context: context)
        widgetSync = WidgetSync(context: context, watch: watchSync)
    }
}

struct AppRootView: View {
    private let services = AppServices.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ContentView()
            .environment(services.engine)
            .environment(services.scanner)
            .environment(services.location)
            .environment(services.geofence)
            .environment(services.deviceMonitor)
            .environment(\.systemLogger, services.logger)
            .environment(\.widgetSync, services.widgetSync)
            .modelContainer(services.container)
            .task { await services.engine.configure(AppSettings.detectorConfiguration) }
            .task { services.widgetSync.start() }
            .onChange(of: scenePhase) { _, phase in
                // Make sure widgets have the latest numbers when the user leaves the app.
                if phase == .background { services.widgetSync.update() }
            }
    }
}
