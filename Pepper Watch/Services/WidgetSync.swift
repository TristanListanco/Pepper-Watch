//
//  WidgetSync.swift
//  Pepper Watch
//

import Foundation
import SwiftData
import SwiftUI
import WidgetKit

/// Keeps the widget snapshot in the App Group container current. Updates are debounced
/// after SwiftData saves so auto-logging while scanning doesn't reload widgets every frame.
final class WidgetSync {
    private let context: ModelContext
    private var pendingUpdate: Task<Void, Never>?
    private var listener: Task<Void, Never>?

    init(context: ModelContext) {
        self.context = context
    }

    func start() {
        update()
        listener = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                self?.scheduleUpdate()
            }
        }
    }

    func scheduleUpdate(after delay: Duration = .seconds(4)) {
        pendingUpdate?.cancel()
        pendingUpdate = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.update()
        }
    }

    func update() {
        Self.makeSnapshot(from: context).save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Builds per-day counts for the last 30 days, overall and per field.
    static func makeSnapshot(from context: ModelContext, now: Date = .now, calendar: Calendar = .current) -> WidgetSnapshot {
        let since = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        let events = (try? context.fetch(FetchDescriptor<DetectionEvent>(
            predicate: #Predicate { $0.timestamp >= since },
            sortBy: [SortDescriptor(\.timestamp)]
        ))) ?? []
        let fields = (try? context.fetch(FetchDescriptor<Field>(sortBy: [SortDescriptor(\.name)]))) ?? []

        func status(id: String, name: String, locationName: String, events: [DetectionEvent]) -> WidgetSnapshot.FieldStatus {
            var byDay: [Date: (aphid: Int, total: Int, scans: Int)] = [:]
            for event in events {
                let day = calendar.startOfDay(for: event.timestamp)
                byDay[day, default: (0, 0, 0)].aphid += event.aphidCount
                byDay[day, default: (0, 0, 0)].total += event.aphidCount + event.healthyCount
                byDay[day, default: (0, 0, 0)].scans += 1
            }
            return WidgetSnapshot.FieldStatus(
                id: id,
                name: name,
                locationName: locationName,
                latestScan: events.last?.timestamp,
                daily: byDay.keys.sorted().map { day in
                    let counts = byDay[day]!
                    return WidgetSnapshot.DailyCount(date: day, aphid: counts.aphid, total: counts.total, scans: counts.scans)
                }
            )
        }

        let fieldStatuses = fields.map { field in
            status(id: field.id.uuidString, name: field.name, locationName: field.locationName, events: events.filter { $0.field?.id == field.id })
        }
        return WidgetSnapshot(
            generatedAt: now,
            overall: status(id: WidgetSnapshot.allFieldsID, name: "All Fields", locationName: "", events: events),
            fields: fieldStatuses
        )
    }
}

extension EnvironmentValues {
    @Entry var widgetSync: WidgetSync?
}
