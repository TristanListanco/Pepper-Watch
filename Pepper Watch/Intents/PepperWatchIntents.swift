//
//  PepperWatchIntents.swift
//  Pepper Watch
//
//  Siri and Shortcuts actions (App Intents, the successor to SiriKit intents).
//

import AppIntents
import SwiftData
import SwiftUI

nonisolated enum PepperWatchIntentError: Error, CustomLocalizedStringResourceConvertible {
    case fieldNotFound

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .fieldNotFound: "That field no longer exists in Pepper Watch."
        }
    }
}

/// Last-7-days numbers for a field (or all fields), shared by the intents.
struct FieldReport {
    let scopeName: String
    /// Cache key used by Insights: "" for all fields, otherwise the field UUID.
    let scopeKey: String
    let weekly: WeeklyInsights

    var stats: InsightsStats { weekly.current }

    static func make(fieldID: UUID?) throws -> FieldReport {
        let context = AppDataStore.container.mainContext
        var events = try context.fetch(FetchDescriptor<DetectionEvent>(sortBy: [SortDescriptor(\.timestamp)]))
        var sessions = try context.fetch(FetchDescriptor<ScanSession>())
        var scopeName = "all fields"
        if let fieldID {
            guard let field = try context.fetch(FetchDescriptor<Field>(predicate: #Predicate { $0.id == fieldID })).first else {
                throw PepperWatchIntentError.fieldNotFound
            }
            scopeName = field.name
            events = events.filter { $0.field?.id == fieldID }
            sessions = sessions.filter { $0.field?.id == fieldID }
        }
        return FieldReport(
            scopeName: scopeName,
            scopeKey: fieldID?.uuidString ?? "",
            weekly: WeeklyInsights(events: events, sessions: sessions, scopeName: scopeName)
        )
    }

    var spokenStatus: String {
        guard stats.totalLeaves > 0, let severity = stats.overallSeverity else {
            return "There are no scans for \(scopeName) in the past 7 days. Open Pepper Watch to scan your field."
        }
        let subject = scopeName == "all fields" ? "Across all fields" : "In \(scopeName)"
        return "\(subject), \(stats.infestationRate.percentText) of leaves were aphid-infested over the past 7 days, across \(stats.scanCount) scans. That's \(severity.title.lowercased()). \(severity.recommendations.first ?? "")"
    }
}

struct CheckFieldStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Check Aphid Status"
    static let description = IntentDescription("Reports the aphid infestation rate and severity for a field over the past 7 days.")

    @Parameter(title: "Field", description: "Leave empty to check all fields.")
    var field: FieldEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Check aphid status for \(\.$field)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let report = try FieldReport.make(fieldID: field?.id)
        let text = report.spokenStatus
        return .result(value: text, dialog: "\(text)", view: FieldStatusSnippet(report: report))
    }
}

struct SummarizeFieldsIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize My Fields"
    static let description = IntentDescription("Summarizes recent aphid scans with Apple Intelligence on this device, or standard highlights when it isn't available.")

    @Parameter(title: "Field", description: "Leave empty to summarize all fields.")
    var field: FieldEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$field)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let report = try FieldReport.make(fieldID: field?.id)
        guard report.stats.totalLeaves > 0 else {
            let text = report.spokenStatus
            return .result(value: text, dialog: "\(text)", view: SummarySnippet(content: HighlightContent(headline: text), isGenerated: false))
        }
        let (content, isGenerated) = await InsightNarrator.summary(for: report.weekly, scope: report.scopeKey)
        // Spoken as one paragraph, so every part needs closing punctuation (headlines usually lack it).
        let text = ([content.headline] + content.observations.map(Optional.some) + [content.recommendation])
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.last.map { ".!?".contains($0) } == true ? $0 : $0 + "." }
            .joined(separator: " ")
        return .result(value: text, dialog: "\(text)", view: SummarySnippet(content: content, isGenerated: isGenerated))
    }
}

struct StartScanningIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Scanning"
    static let description = IntentDescription("Opens the Pepper Watch scanner for a field.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Field", description: "Leave empty to pick from your fields.")
    var field: FieldEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Start scanning \(\.$field)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.startScanning(fieldID: field?.id)
        return .result()
    }
}

struct ShowInsightsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Insights"
    static let description = IntentDescription("Opens the Pepper Watch Insights dashboard.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Field", description: "Leave empty to show all fields.")
    var field: FieldEntity?

    @MainActor
    func perform() async throws -> some IntentResult {
        AppNavigator.shared.showInsights(fieldID: field?.id)
        return .result()
    }
}

nonisolated struct PepperWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckFieldStatusIntent(),
            phrases: [
                "Check aphids in \(.applicationName)",
                "Check aphid status in \(.applicationName)",
                "How is \(\.$field) in \(.applicationName)",
            ],
            shortTitle: "Aphid Status",
            systemImageName: "ant"
        )
        AppShortcut(
            intent: SummarizeFieldsIntent(),
            phrases: [
                "Summarize my fields in \(.applicationName)",
                "Give me a \(.applicationName) summary",
                "Summarize \(\.$field) in \(.applicationName)",
            ],
            shortTitle: "Summarize Fields",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: StartScanningIntent(),
            phrases: [
                "Start scanning in \(.applicationName)",
                "Scan \(\.$field) with \(.applicationName)",
            ],
            shortTitle: "Start Scanning",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: ShowInsightsIntent(),
            phrases: [
                "Show \(.applicationName) insights",
                "Open insights in \(.applicationName)",
            ],
            shortTitle: "Insights",
            systemImageName: "chart.bar.xaxis"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .lime
}
