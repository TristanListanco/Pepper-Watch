//
//  WatchTests.swift
//  PepperWatchWatchTests
//
//  The watch app and the code it shares with its widgets: field order, chart trends, the Siri
//  summary, the week's numbers and the morning refresh time.
//

import Foundation
import Testing
@testable import PepperWatchWatchApp

/// A fixed "now" keeps day windows stable whatever day the tests run.
private let now = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 12))!

private func day(_ offset: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: offset, to: Calendar.current.startOfDay(for: now))!
}

private func field(_ id: String, name: String? = nil, daily: [WidgetSnapshot.DailyCount] = []) -> WidgetSnapshot.FieldStatus {
    WidgetSnapshot.FieldStatus(id: id, name: name ?? id, locationName: "", latestScan: nil, daily: daily)
}

@Suite("Field order")
struct FieldOrderTests {
    private let fields = [field("a"), field("b"), field("c")]

    @Test func savedOrderComesFirst() {
        #expect(WatchStore.ordered(fields, order: "c,a").map(\.id) == ["c", "a", "b"])
    }

    @Test func noSavedOrderKeepsTheIPhoneOrder() {
        #expect(WatchStore.ordered(fields, order: "").map(\.id) == ["a", "b", "c"])
    }

    @Test func removedFieldsInTheSavedOrderAreIgnored() {
        #expect(WatchStore.ordered(fields, order: "gone,b").map(\.id) == ["b", "a", "c"])
    }

    @Test("Dragging moves a field before another or to the end", arguments: [
        (["c"], "a", "c,a,b"),
        (["a"], nil, "b,c,a"),
        (["a", "b"], "c", "a,b,c"),
    ] as [([String], String?, String)])
    func reordering(sources: [String], destination: String?, expected: String) {
        #expect(WatchStore.reordering(fields, sources: sources, before: destination) == expected)
    }
}

@Suite("Chart trends")
struct TrendTests {
    private func bucket(_ offset: Int, aphid: Int = 0, total: Int = 0, scans: Int = 0) -> WatchPayload.TrendBucket {
        WatchPayload.TrendBucket(start: day(offset), aphid: aphid, total: total, scans: scans)
    }

    private var trend: WatchPayload.Trend {
        WatchPayload.Trend(
            buckets: [bucket(-3), bucket(-2), bucket(-1, aphid: 2, total: 10, scans: 1), bucket(0, aphid: 3, total: 10, scans: 2)],
            previous: bucket(-10, aphid: 1, total: 10, scans: 1)
        )
    }

    @Test("Month-long views start at the first period with data", arguments: [TrendRange.sixMonths, .year])
    func monthViewsTrimLeadingEmptyPeriods(range: TrendRange) {
        #expect(trend.startingWithData(for: range).buckets.count == 2)
    }

    @Test("Shorter views keep every period", arguments: [TrendRange.day, .week, .month])
    func shortViewsKeepEveryPeriod(range: TrendRange) {
        #expect(trend.startingWithData(for: range).buckets.count == 4)
    }

    @Test func totalsAndChangeAgainstThePreviousPeriod() throws {
        #expect(trend.aphid == 5)
        #expect(trend.total == 20)
        #expect(trend.scans == 3)
        #expect(trend.rate == 0.25)
        // 25% now against 10% before.
        let change = try #require(trend.change)
        #expect(abs(change - 15) < 0.0001)
    }

    @Test func noLeavesMeansNoRateOrChange() {
        let empty = WatchPayload.Trend(buckets: [bucket(0)], previous: bucket(-7))
        #expect(empty.rate == nil)
        #expect(empty.change == nil)
    }
}

@Suite("Week at a glance")
struct ScopeStatsTests {
    @Test func weekComparesWithThePreviousWeek() throws {
        let status = field("a", daily: [
            .init(date: day(0), aphid: 5, total: 10, scans: 1),
            .init(date: day(-9), aphid: 1, total: 10, scans: 1),
        ])
        let stats = ScopeStats(status, now: now)
        #expect(stats.days.count == 7)
        #expect(stats.hasLeaves)
        #expect(stats.healthyLeaves == 5)
        let change = try #require(stats.change)
        #expect(abs(change - 40) < 0.0001)
    }

    @Test func noPreviousWeekMeansNoChange() {
        let stats = ScopeStats(field("a", daily: [.init(date: day(0), aphid: 1, total: 4, scans: 1)]), now: now)
        #expect(stats.change == nil)
    }
}

@Suite("Siri summary")
struct SiriSummaryTests {
    @Test func describesSeverityRateAndChange() {
        let status = field("a", name: "Field A", daily: [
            .init(date: day(0), aphid: 4, total: 10, scans: 1),
            .init(date: day(-9), aphid: 1, total: 10, scans: 1),
        ])
        let summary = CheckFieldIntent.summary(of: status, now: now)
        #expect(summary.hasPrefix("Field A is moderate: 40% of leaves showed aphid damage this week"))
        #expect(summary.contains("up 30 points"))
    }

    @Test func saysWhenAFieldHasNoScans() {
        #expect(CheckFieldIntent.summary(of: field("a", name: "Greenhouse 1"), now: now) == "Greenhouse 1 has no scans this week.")
    }
}

@Suite("Morning refresh")
struct DailyRefreshTests {
    private func time(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: now)!
    }

    @Test func beforeFiveRunsThisMorning() {
        let run = DailyRefresh.nextRun(after: time(hour: 3))
        #expect(Calendar.current.isDate(run, inSameDayAs: now))
        #expect(Calendar.current.component(.hour, from: run) == 5)
    }

    @Test("From five onward it runs tomorrow", arguments: [5, 12, 23])
    func afterFiveRunsTomorrow(hour: Int) {
        let run = DailyRefresh.nextRun(after: time(hour: hour))
        #expect(Calendar.current.isDate(run, inSameDayAs: day(1)))
        #expect(Calendar.current.component(.hour, from: run) == 5)
    }
}
