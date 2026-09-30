//
//  WatchIntents.swift
//  Pepper Watch (Apple Watch)
//
//  Siri on the watch (App Intents): a field's status from the numbers synced to the watch, so it
//  answers without the iPhone nearby.
//

import AppIntents
import Foundation

struct CheckFieldIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Field"
    static let description = IntentDescription("Tells you a field's aphid status this week, from the numbers on your watch.")

    @Parameter(title: "Field", description: "Leave empty for your first field.")
    var field: WatchFieldEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Check \(\.$field)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let fields = WatchStore.ordered(WatchStore.payload?.snapshot.fields ?? [])
        guard let status = fields.first(where: { $0.id == field?.id }) ?? fields.first else {
            return .result(dialog: "Open Pepper Watch on your iPhone to sync your fields.")
        }
        let summary = Self.summary(of: status)
        return .result(dialog: "\(summary)")
    }

    /// "Field A is moderate: 49% of leaves showed aphid damage this week, up 27 points. Last scanned 4 days ago."
    static func summary(of status: WidgetSnapshot.FieldStatus, now: Date = .now) -> String {
        let stats = ScopeStats(status, now: now)
        guard stats.hasLeaves else {
            return "\(status.name) has no scans this week."
        }
        var sentence = "\(status.name) is \(stats.current.severity?.title.lowercased() ?? "clear"): \(stats.current.infestationRate.percentText) of leaves showed aphid damage this week"
        if let change = stats.change, abs(change) >= 1 {
            sentence += ", \(change > 0 ? "up" : "down") \(Int(abs(change).rounded())) points"
        }
        sentence += "."
        if let latest = status.latestScan {
            sentence += " Last scanned \(latest.formatted(.relative(presentation: .named)))."
        }
        return sentence
    }
}

/// Siri phrases for the watch. The field names come from the synced fields.
struct PepperWatchWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckFieldIntent(),
            phrases: [
                "Check aphids in \(.applicationName)",
                "Check \(\.$field) in \(.applicationName)",
                "How is \(\.$field) in \(.applicationName)",
            ],
            shortTitle: "Check Field",
            systemImageName: "leaf.fill"
        )
    }
}
