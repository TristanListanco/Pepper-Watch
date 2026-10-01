//
//  SharedModelTests.swift
//  PepperWatchTests
//
//  Code shared with the widgets and the watch: the widget snapshot's 7-day windows, Smart Stack
//  relevance and the watch payload's encoding.
//

import CoreLocation
import Foundation
import Testing
@testable import Pepper_Watch

/// A fixed "now" keeps day windows stable whatever day the tests run.
private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!

private func day(_ offset: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: now))!
}

private func field(
    id: String = "field-a",
    daily: [WidgetSnapshot.DailyCount] = [],
    latestScan: Date? = nil,
    latitude: Double? = 8.61,
    longitude: Double? = 124.89
) -> WidgetSnapshot.FieldStatus {
    WidgetSnapshot.FieldStatus(
        id: id, name: "Field A", locationName: "Claveria", latestScan: latestScan, daily: daily,
        latitude: latitude, longitude: longitude, radiusMeters: 60
    )
}

@Suite("Widget snapshot")
struct WidgetSnapshotTests {
    @Test func weekWindowSumsTheLastSevenDays() {
        let status = field(daily: [
            .init(date: day(0), aphid: 2, total: 10, scans: 1),
            .init(date: day(-6), aphid: 3, total: 10, scans: 2),
            // Eight days ago falls outside this week.
            .init(date: day(-8), aphid: 9, total: 9, scans: 5),
        ])
        let week = status.window(now: now)
        #expect(week.aphidLeaves == 5)
        #expect(week.totalLeaves == 20)
        #expect(week.scans == 3)
        #expect(week.infestationRate == 0.25)
        #expect(week.severity == .moderate)
        #expect(week.daily.map(\.date) == [day(-6), day(0)])
    }

    @Test func previousWeekWindowUsesTheOffset() {
        let status = field(daily: [.init(date: day(-8), aphid: 9, total: 9, scans: 5)])
        let previous = status.window(offset: 7, now: now)
        #expect(previous.totalLeaves == 9)
        #expect(previous.severity == .severe)
    }

    @Test func emptyWindowHasNoSeverity() {
        #expect(field().window(now: now).severity == nil)
    }

    @Test func unknownFieldFallsBackToAllFields() {
        let overall = field(id: WidgetSnapshot.allFieldsID)
        let snapshot = WidgetSnapshot(generatedAt: now, overall: overall, fields: [field(id: "a")])
        #expect(snapshot.status(forFieldID: "a").id == "a")
        #expect(snapshot.status(forFieldID: "missing").id == WidgetSnapshot.allFieldsID)
        #expect(snapshot.status(forFieldID: nil).id == WidgetSnapshot.allFieldsID)
    }
}

@Suite("Smart Stack relevance")
struct FieldRelevanceTests {
    @Test("Worse infestation ranks higher", arguments: [
        (0, 10, Float(0.2)),   // clear
        (1, 10, 0.4),          // low
        (3, 10, 0.7),          // moderate
        (6, 10, 1.0),          // severe
    ])
    func scoreFollowsSeverity(aphid: Int, total: Int, expected: Float) {
        let status = field(daily: [.init(date: day(0), aphid: aphid, total: total, scans: 1)], latestScan: now)
        #expect(FieldRelevance.score(for: status, now: now) == expected)
    }

    @Test func noFieldScoresZero() {
        #expect(FieldRelevance.score(for: nil, now: now) == 0)
    }

    @Test func fieldDueForScoutingScoresAtLeastHalf() {
        // Clear, but last scanned four days ago.
        let status = field(daily: [.init(date: day(-4), aphid: 0, total: 10, scans: 1)], latestScan: day(-4))
        #expect(FieldRelevance.isDueForScouting(status, now: now))
        #expect(FieldRelevance.score(for: status, now: now) == 0.5)
    }

    @Test func locationContextNeedsCoordinates() {
        let located = FieldRelevance.contexts(for: [field(latestScan: now)], now: now, includeTiming: false)
        let unlocated = FieldRelevance.contexts(for: [field(latestScan: now, latitude: nil, longitude: nil)], now: now, includeTiming: false)
        #expect(located.count == 1)
        #expect(unlocated.isEmpty)
    }

    @Test func timingAddsContextsForSevereAndDueFields() {
        let severeAndDue = field(daily: [.init(date: day(-3), aphid: 8, total: 10, scans: 1)], latestScan: day(-3))
        let contexts = FieldRelevance.contexts(for: [severeAndDue], now: now)
        // Location, the next six hours while severe, and the next scouting morning.
        #expect(contexts.count == 3)
    }

    @Test("The scouting window is 6–10 AM, today or tomorrow", arguments: [
        (5, 0, 6),      // before 6: today from 6
        (8, 0, 8),      // during: from now
        (11, 1, 6),     // after 10: tomorrow from 6
    ])
    func scoutingWindow(hour: Int, dayOffset: Int, startHour: Int) throws {
        let calendar = Calendar.current
        let moment = try #require(calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now))
        let window = try #require(FieldRelevance.nextScoutingWindow(after: moment))
        let expectedDay = try #require(calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)))
        #expect(calendar.isDate(window.start, inSameDayAs: expectedDay))
        #expect(calendar.component(.hour, from: window.start) == startHour)
        #expect(calendar.component(.hour, from: window.end) == 10)
    }
}

@Suite("Watch payload")
struct WatchPayloadTests {
    @Test func roundTripsThroughJSON() throws {
        let snapshot = WidgetSnapshot(generatedAt: now, overall: field(id: WidgetSnapshot.allFieldsID), fields: [field()])
        let trend = WatchPayload.Trend(
            buckets: [.init(start: day(-1), aphid: 2, total: 8, scans: 1)],
            previous: .init(start: day(-8), aphid: 1, total: 4, scans: 1)
        )
        let payload = WatchPayload(snapshot: snapshot, highlights: [:], trends: ["field-a": ["W": trend]])
        let data = try #require(payload.encoded())
        let decoded = try #require(WatchPayload.decoded(from: data))
        #expect(decoded.snapshot.fields.first?.id == "field-a")
        #expect(decoded.trends?["field-a"]?["W"] == trend)
    }

    @Test func trendBucketsUseShortKeys() throws {
        // Payloads have a size budget, so buckets encode with one-letter keys.
        let data = try JSONEncoder().encode(WatchPayload.TrendBucket(start: now, aphid: 1, total: 2, scans: 3))
        let keys = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys
        #expect(Set(keys) == ["s", "a", "t", "n"])
    }

    @Test func rangesCycleThroughAllFive() {
        var range = WatchPayload.TrendRange.day
        var seen: [WatchPayload.TrendRange] = []
        for _ in 0..<5 {
            seen.append(range)
            range = range.next
        }
        #expect(seen == [.day, .week, .month, .sixMonths, .year])
        #expect(range == .day)
    }
}
