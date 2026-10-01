//
//  PersistenceTests.swift
//  PepperWatchTests
//
//  SwiftData-backed behavior on an in-memory store: CSV export, log pruning and which scan
//  sessions count toward performance readings.
//

import Foundation
import SwiftData
import Testing
@testable import Pepper_Watch

/// A fresh in-memory store with the app's schema for each test.
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(for: AppSchema.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return ModelContext(container)
}

private let metrics = DeviceMetrics.Snapshot(thermalState: .nominal, memoryMB: 120, batteryPercent: 80)

@Suite("CSV export", .tags(.export))
struct CSVExportTests {
    @Test func sessionsHaveAHeaderAndOneRowEach() throws {
        let context = try makeContext()
        let session = ScanSession(fieldName: "North Plot", computeUnits: "All", startedAt: .now)
        session.framesProcessed = 120
        session.averageFPS = 21.5
        context.insert(session)

        let lines = CSVExporter.sessions([session]).text.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.first?.hasPrefix("session_id,started_at") == true)
        #expect(lines.last?.contains("North Plot") == true)
        #expect(lines.last?.contains("21.50") == true)
    }

    @Test func fieldNamesWithCommasAndQuotesAreEscaped() throws {
        let context = try makeContext()
        let session = ScanSession(fieldName: #"Row 3, "east""#, computeUnits: "All")
        context.insert(session)
        let row = try #require(CSVExporter.sessions([session]).text.split(separator: "\n").last)
        #expect(row.contains(#""Row 3, ""east""""#))
    }

    @Test func fileNamesCarryTheKindAndDate() {
        let document = CSVExporter.sessions([])
        #expect(document.filename.hasPrefix("pepper-watch-sessions-"))
        #expect(document.filename.hasSuffix(".csv"))
    }

    @Test func writesTheFileForSharing() async throws {
        let document = CSVDocument(filename: "pepper-watch-test.csv", text: "a,b\n1,2")
        let url = try await document.writeToTemporaryFile()
        #expect(url.lastPathComponent == "pepper-watch-test.csv")
        #expect(try String(contentsOf: url, encoding: .utf8) == "a,b\n1,2")
    }
}

@Suite("Daily upkeep")
struct MaintenanceTests {
    @Test func prunesOnlyLogsOlderThanThirtyDays() throws {
        let context = try makeContext()
        let now = Date.now
        for age in [0, 10, 29, 31, 45] {
            let log = SystemLog(level: .info, category: "health", message: "\(age) days", metrics: metrics)
            log.timestamp = now.addingTimeInterval(-Double(age) * 86_400)
            context.insert(log)
        }
        try context.save()

        let removed = AppMaintenance.pruneLogs(in: context, now: now)
        #expect(removed == 2)
        let remaining = try context.fetch(FetchDescriptor<SystemLog>()).map(\.message).sorted()
        #expect(remaining == ["0 days", "10 days", "29 days"])
    }

    @Test func nothingToPruneRemovesNothing() throws {
        let context = try makeContext()
        #expect(AppMaintenance.pruneLogs(in: context) == 0)
    }
}

@Suite("Performance readings")
struct ThroughputReadingTests {
    @Test func onlyFinishedRealScansCount() throws {
        let context = try makeContext()
        let finished = ScanSession(fieldName: "A", computeUnits: "All")
        finished.endedAt = .now
        finished.framesProcessed = 300
        let running = ScanSession(fieldName: "B", computeUnits: "All")
        running.framesProcessed = 50
        let demo = ScanSession(fieldName: "C", computeUnits: "All")
        demo.endedAt = .now
        demo.framesProcessed = 300
        demo.isDemo = true
        let empty = ScanSession(fieldName: "D", computeUnits: "All")
        empty.endedAt = .now
        [finished, running, demo, empty].forEach(context.insert)

        #expect(ThroughputReading.isMeasured(finished))
        #expect(!ThroughputReading.isMeasured(running))
        #expect(!ThroughputReading.isMeasured(demo))
        #expect(!ThroughputReading.isMeasured(empty))
    }
}

extension Tag {
    @Tag static var export: Self
}
