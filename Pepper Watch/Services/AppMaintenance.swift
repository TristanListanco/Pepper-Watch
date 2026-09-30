//
//  AppMaintenance.swift
//  Pepper Watch
//
//  Daily upkeep in the background (BackgroundTasks): trims old System Log entries, which grow by
//  a health check every 30 seconds of scanning, and refreshes widgets and the watch for the new day.
//

import BackgroundTasks
import Foundation
import SwiftData

enum AppMaintenance {
    /// Listed under BGTaskSchedulerPermittedIdentifiers in PepperWatch-Info.plist.
    static let refreshTaskID = "com.tristanlistanco.Pepper-Watch.refresh"
    /// System Log entries older than this are removed.
    static let logRetention: TimeInterval = 30 * 86_400

    /// Asks iOS for a run from early tomorrow morning; the system picks the moment.
    static func scheduleRefresh(now: Date = .now, calendar: Calendar = .current) {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let earliest = calendar.date(byAdding: .hour, value: 3, to: tomorrow)
        Task {
            let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
            request.earliestBeginDate = earliest
            // Replaces an earlier pending request with the same identifier.
            try? await BGTaskScheduler.shared.submitTaskRequest(request)
        }
    }

    /// Runs when iOS wakes the app for the refresh task.
    static func run() {
        // Chain the next run first, so a cut-short run still leaves one scheduled.
        scheduleRefresh()
        let services = AppServices.shared
        let removed = pruneLogs(in: services.container.mainContext)
        services.widgetSync.update()
        if removed > 0 {
            services.logger.log(category: "maintenance", "Removed \(removed) log entries older than 30 days")
        }
    }

    /// Deletes old System Log entries in one batch and returns how many there were.
    @discardableResult
    static func pruneLogs(in context: ModelContext, now: Date = .now) -> Int {
        let cutoff = now.addingTimeInterval(-logRetention)
        let old = #Predicate<SystemLog> { $0.timestamp < cutoff }
        let count = (try? context.fetchCount(FetchDescriptor(predicate: old))) ?? 0
        guard count > 0 else { return 0 }
        try? context.delete(model: SystemLog.self, where: old)
        try? context.save()
        return count
    }
}
