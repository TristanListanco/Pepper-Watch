//
//  Pepper_WatchApp.swift
//  Pepper Watch
//
//  Created by Tristan Listanco on 9/29/26.
//

import AppIntents
import SwiftData
import SwiftUI

@main
struct Pepper_WatchApp: App {
    init() {
        AppSettings.registerDefaults()
        PepperWatchTips.configure()
        // Activate WatchConnectivity at launch, including background launches the watch triggers.
        AppServices.shared.watchSync.start()
        // The Scan Leaves control's intent runs here and opens the Scan tab.
        AppDependencyManager.shared.add(dependency: ScannerLauncher { AppNavigator.shared.startScanning(fieldID: nil) })
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        // The iPadOS menu bar, and keyboard shortcuts with a hardware keyboard.
        .commands { PepperWatchCommands() }
        // Daily upkeep scheduled with BGTaskScheduler (see AppMaintenance).
        .backgroundTask(.appRefresh(AppMaintenance.refreshTaskID)) {
            await MainActor.run { AppMaintenance.run() }
        }
    }
}

/// File › New Field and a Go menu for the tabs, with shortcuts.
struct PepperWatchCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Field", systemImage: "plus") {
                AppNavigator.shared.requestNewField()
            }
            .keyboardShortcut("n")
        }
        CommandMenu("Go") {
            Button("Scan", systemImage: "camera.viewfinder") { AppNavigator.shared.selectedTab = .scan }
                .keyboardShortcut("1")
            Button("Insights", systemImage: "chart.bar.xaxis") { AppNavigator.shared.selectedTab = .insights }
                .keyboardShortcut("2")
            Button("History", systemImage: "square.grid.2x2") { AppNavigator.shared.selectedTab = .history }
                .keyboardShortcut("3")
            Button("Developer", systemImage: "hammer") { AppNavigator.shared.selectedTab = .developer }
                .keyboardShortcut("4")
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
    let metrics: MetricsCollector
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
        metrics = MetricsCollector(logger: logger)
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
            .environment(services.metrics)
            .environment(\.systemLogger, services.logger)
            .environment(\.widgetSync, services.widgetSync)
            .modelContainer(services.container)
            .task { await services.engine.configure(AppSettings.detectorConfiguration) }
            .task { services.widgetSync.start() }
            .task { services.metrics.start() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .background else { return }
                // Make sure widgets have the latest numbers when the user leaves the app,
                // and keep tomorrow's upkeep scheduled.
                services.widgetSync.update()
                AppMaintenance.scheduleRefresh()
            }
    }
}
