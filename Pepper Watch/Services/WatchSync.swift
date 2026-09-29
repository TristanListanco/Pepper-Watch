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
        let payload = WatchPayload(snapshot: snapshot, highlights: highlights())
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
