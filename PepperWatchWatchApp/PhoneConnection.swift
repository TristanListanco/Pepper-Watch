//
//  PhoneConnection.swift
//  Pepper Watch (Apple Watch)
//

import AppIntents
import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// Receives field stats and highlights from the paired iPhone and keeps the latest copy in the
/// App Group, so the app and its Smart Stack widgets work even when the iPhone is out of range.
@Observable
final class PhoneConnection: NSObject {
    private(set) var payload: WatchPayload?
    private(set) var isRequesting = false

    override init() {
        super.init()
        payload = WatchStore.payload
    }

    func start() {
        // Scouting reminders are time based, so refresh them every time the app opens.
        donateRelevance()
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Asks the iPhone for the latest numbers. Does nothing when it isn't reachable;
    /// the iPhone also pushes updates on its own after every scan.
    func requestUpdate() async {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable, !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        let data: Data? = await withCheckedContinuation { continuation in
            session.sendMessage([WatchPayload.requestKey: true]) { @Sendable reply in
                continuation.resume(returning: reply[WatchPayload.contextKey] as? Data)
            } errorHandler: { @Sendable _ in
                continuation.resume(returning: nil)
            }
        }
        if let data { apply(data) }
    }

    /// Background delivery: the system wakes the app when the iPhone sends new data while it's
    /// suspended. Keep the task open until the session has handed everything to the delegate.
    func receivePendingContent() async {
        start()
        let session = WCSession.default
        let deadline = ContinuousClock.now + .seconds(10)
        while session.activationState != .activated || session.hasContentPending, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func apply(_ data: Data) {
        guard let decoded = WatchPayload.decoded(from: data) else { return }
        // Ignore anything older than what's already shown.
        if let payload, payload.snapshot.generatedAt > decoded.snapshot.generatedAt { return }
        payload = decoded
        WatchStore.savePayload(data)
        WidgetCenter.shared.reloadAllTimelines()
        // Field locations may have changed, so let the Smart Stack re-check where each widget is relevant.
        WidgetCenter.shared.invalidateRelevance(ofKind: WatchWidgetKind.fieldStatus)
        WidgetCenter.shared.invalidateRelevance(ofKind: WatchWidgetKind.atField)
        donateRelevance()
    }

    /// Tells the Smart Stack, through RelevantContext, when each field's widget matters: at the
    /// field, the morning it's due for scouting, and while it's moderate or severe.
    private func donateRelevance() {
        let intents = WatchRelevance.contexts().map {
            RelevantIntent(WatchFieldIntent(field: WatchFieldEntity($0.field)), widgetKind: WatchWidgetKind.fieldStatus, relevance: $0.relevance)
        }
        Task { try? await RelevantIntentManager.shared.updateRelevantIntents(intents) }
    }
}

extension PhoneConnection: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let data = session.receivedApplicationContext[WatchPayload.contextKey] as? Data
        Task { @MainActor in
            if let data { self.apply(data) }
            await self.requestUpdate()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchPayload.contextKey] as? Data else { return }
        Task { @MainActor in self.apply(data) }
    }
}
