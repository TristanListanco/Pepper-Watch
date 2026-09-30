//
//  WatchSync.swift
//  Pepper Watch
//

import Foundation
import SwiftData
import Synchronization
import WatchConnectivity

/// Sends field stats and highlights to the paired Apple Watch. The application context always
/// holds the newest payload, so the watch catches up whenever it launches or reconnects.
final class WatchSync: NSObject {
    private let context: ModelContext
    /// The newest encoded payload, readable from WatchConnectivity's delegate queue so refresh
    /// requests from the watch are answered straight away.
    private let latestPayload = Mutex<Data?>(nil)

    init(context: ModelContext) {
        self.context = context
    }

    func start() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Builds the payload for `snapshot` and hands it to the watch when the Pepper Watch app is installed on it.
    func send(_ snapshot: WidgetSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let payload = WatchPayload(snapshot: snapshot, highlights: highlights(), validation: validation(), trends: trends())
        guard let data = payload.encoded() else { return }
        latestPayload.withLock { $0 = data }
        try? session.updateApplicationContext([WatchPayload.contextKey: data])
    }

    private func sendCurrent() {
        send(WidgetSync.makeSnapshot(from: context))
    }

    /// Apple Intelligence summaries cached on this iPhone while they still match the numbers,
    /// otherwise rule-based highlights. Scope keys and names match InsightsView so cached summaries are found.
    private func highlights() -> [String: WatchPayload.Highlight] {
        let events = (try? context.fetch(FetchDescriptor<DetectionEvent>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<ScanSession>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        let fields = (try? context.fetch(FetchDescriptor<Field>())) ?? []

        var result = [WidgetSnapshot.allFieldsID: highlight(WeeklyInsights(events: events, sessions: sessions, scopeName: "all fields"), scope: "")]
        for field in fields {
            let insights = WeeklyInsights(
                events: events.filter { $0.field?.id == field.id },
                sessions: sessions.filter { $0.field?.id == field.id },
                scopeName: field.name
            )
            result[field.id.uuidString] = highlight(insights, scope: field.id.uuidString)
        }
        return result
    }

    /// Hourly, daily, weekly and monthly totals for each range the watch offers, overall and per field.
    private func trends(now: Date = .now) -> [String: [String: WatchPayload.Trend]] {
        let since = Calendar.current.date(byAdding: .year, value: -2, to: now) ?? now
        let events = (try? context.fetch(FetchDescriptor<DetectionEvent>(predicate: #Predicate { $0.timestamp >= since }))) ?? []
        let fields = (try? context.fetch(FetchDescriptor<Field>())) ?? []
        var result = [WidgetSnapshot.allFieldsID: Self.trends(for: events, now: now)]
        for field in fields {
            result[field.id.uuidString] = Self.trends(for: events.filter { $0.field?.id == field.id }, now: now)
        }
        return result
    }

    private static func trends(for events: [DetectionEvent], now: Date, calendar: Calendar = .current) -> [String: WatchPayload.Trend] {
        var result: [String: WatchPayload.Trend] = [:]
        for range in WatchPayload.TrendRange.allCases {
            let (component, count) = range.bucket
            guard let current = calendar.dateInterval(of: component, for: now)?.start,
                  let first = calendar.date(byAdding: component, value: -(count - 1), to: current),
                  let previousStart = calendar.date(byAdding: component, value: -count, to: first)
            else { continue }
            var buckets = (0..<count).map { offset in
                WatchPayload.TrendBucket(start: calendar.date(byAdding: component, value: offset, to: first) ?? first, aphid: 0, total: 0, scans: 0)
            }
            var previous = WatchPayload.TrendBucket(start: previousStart, aphid: 0, total: 0, scans: 0)
            for event in events where event.timestamp >= previousStart {
                let leaves = event.aphidCount + event.healthyCount
                if event.timestamp < first {
                    previous.aphid += event.aphidCount
                    previous.total += leaves
                    previous.scans += 1
                } else if let start = calendar.dateInterval(of: component, for: event.timestamp)?.start,
                          let index = calendar.dateComponents([component], from: first, to: start).value(for: component),
                          buckets.indices.contains(index) {
                    buckets[index].aphid += event.aphidCount
                    buckets[index].total += leaves
                    buckets[index].scans += 1
                }
            }
            result[range.rawValue] = WatchPayload.Trend(buckets: buckets, previous: previous)
        }
        return result
    }

    /// Every verified detection, overall and per field. Verifications are sparse, so this isn't limited to a week.
    private func validation() -> [String: WatchPayload.Validation] {
        let events = (try? context.fetch(FetchDescriptor<DetectionEvent>())) ?? []
        var metrics: [String: ValidationMetrics] = [:]
        for event in events {
            for box in event.boxes {
                guard let verdict = box.verdict else { continue }
                metrics[WidgetSnapshot.allFieldsID, default: ValidationMetrics()].add(predicted: box.leafClass, verdict: verdict)
                if let fieldID = event.field?.id.uuidString {
                    metrics[fieldID, default: ValidationMetrics()].add(predicted: box.leafClass, verdict: verdict)
                }
            }
        }
        return metrics.mapValues {
            WatchPayload.Validation(
                truePositives: $0.truePositives,
                falsePositives: $0.falsePositives,
                trueNegatives: $0.trueNegatives,
                falseNegatives: $0.falseNegatives
            )
        }
    }

    private func highlight(_ insights: WeeklyInsights, scope: String) -> WatchPayload.Highlight {
        if let cached = InsightNarrator.cachedSummary(for: insights, scope: scope) {
            return WatchPayload.Highlight(
                headline: cached.content.headline,
                observations: cached.content.observations,
                recommendation: cached.content.recommendation,
                isGenerated: true,
                generatedAt: cached.generatedAt
            )
        }
        return WatchPayload.Highlight(
            headline: insights.fallback.headline,
            observations: insights.fallback.observations,
            recommendation: insights.fallback.recommendation,
            isGenerated: false,
            generatedAt: nil
        )
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.sendCurrent() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        // Covers the watch app being installed after the iPhone app launched.
        Task { @MainActor in self.sendCurrent() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another watch; activate again to talk to it.
        session.activate()
    }

    /// The watch asks for data when it opens. Reply with the newest payload now, then push a fresh one.
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let data = latestPayload.withLock { $0 }
        replyHandler(data.map { [WatchPayload.contextKey: $0] } ?? [:])
        Task { @MainActor in self.sendCurrent() }
    }
}
