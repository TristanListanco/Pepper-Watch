//
//  InsightNarrator.swift
//  Pepper Watch
//
//  Turns dashboard numbers into a short plain-language briefing with the on-device
//  Apple Intelligence model. Falls back to rule-based highlights when unavailable.
//

import Foundation
import FoundationModels
import Observation

@Generable
nonisolated struct FieldInsightReport {
    @Guide(description: "A short headline about the aphid situation, at most 10 words")
    var headline: String

    @Guide(description: "Two or three brief observations, each citing a number from the facts. Lead with the change from the previous week when it is given.", .count(2...3))
    var observations: [String]

    @Guide(description: "One practical, low-risk next step for the farmer in a single sentence")
    var recommendation: String
}

/// What the highlights card shows, whether generated or rule-based.
struct HighlightContent: Equatable, Codable {
    var headline: String?
    var observations: [String] = []
    var recommendation: String?
}

/// A generated summary saved on device so it's reused until the underlying numbers change.
private struct CachedReport: Codable {
    var facts: String
    var content: HighlightContent
    var generatedAt: Date
}

@Observable
final class InsightNarrator {
    enum Phase: Equatable {
        case idle
        case generating
        case generated
        case unavailable(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var content = HighlightContent()
    /// When the shown summary was generated (restored from cache or just created).
    private(set) var generatedAt: Date?

    @ObservationIgnored private var lastRequest: (facts: String, scope: String)?
    @ObservationIgnored private var generation: Task<Void, Never>?

    private static let cacheKey = "insights.aiReportCache"
    private static let maximumCachedScopes = 12

    private static let instructions = """
    You are the scouting assistant in Pepper Watch, an offline app that detects aphid damage on bell pepper \
    leaves with an on-device model. Summarize the statistics you are given for a smallholder farmer in \
    Northern Mindanao, Philippines. Use only the numbers provided and never invent data. Write plain, short \
    sentences. Recommendations must be low-risk integrated pest management steps, such as checking leaf \
    undersides, removing infested leaves, spraying water, applying insecticidal soap or neem oil according \
    to the label, protecting lady beetles, re-scanning, or contacting the municipal agriculturist. Never name \
    specific chemical pesticides or doses.
    """

    /// Describes why generation isn't possible, or `nil` when the on-device model is ready.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.deviceNotEligible):
            return "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in Settings for generated insights."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still getting ready. Try again later."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        }
    }

    /// Shows the cached summary for `scope` when the facts are unchanged; generates a new one only
    /// when the numbers changed or the user asks to regenerate.
    func refresh(facts: String, scope: String, force: Bool = false) {
        if !force, let lastRequest, lastRequest.facts == facts, lastRequest.scope == scope { return }
        lastRequest = (facts, scope)

        if !force, let cached = Self.loadCache()[scope], cached.facts == facts {
            generation?.cancel()
            content = cached.content
            generatedAt = cached.generatedAt
            phase = .generated
            return
        }
        if let reason = Self.unavailableReason {
            phase = .unavailable(reason)
            return
        }
        generation?.cancel()
        generation = Task { await generate(from: facts, scope: scope) }
    }

    private func generate(from facts: String, scope: String) async {
        phase = .generating
        content = HighlightContent()
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let stream = session.streamResponse(to: facts, generating: FieldInsightReport.self)
            for try await snapshot in stream {
                guard !Task.isCancelled else { return }
                content = HighlightContent(
                    headline: snapshot.content.headline,
                    observations: snapshot.content.observations ?? [],
                    recommendation: snapshot.content.recommendation
                )
            }
            generatedAt = .now
            phase = .generated
            Self.save(CachedReport(facts: facts, content: content, generatedAt: .now), for: scope)
        } catch is CancellationError {
            // A newer request replaced this one.
        } catch {
            lastRequest = nil
            phase = .failed(error.localizedDescription)
        }
    }

    /// One-shot summary for Siri and Shortcuts. Reuses the cached report when the facts match,
    /// generates on device when possible, and otherwise returns the rule-based highlights.
    static func summary(for insights: WeeklyInsights, scope: String) async -> (content: HighlightContent, isGenerated: Bool) {
        if let cached = loadCache()[scope], cached.facts == insights.facts {
            return (cached.content, true)
        }
        guard unavailableReason == nil else { return (insights.fallback, false) }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: insights.facts, generating: FieldInsightReport.self)
            let content = HighlightContent(
                headline: response.content.headline,
                observations: response.content.observations,
                recommendation: response.content.recommendation
            )
            save(CachedReport(facts: insights.facts, content: content, generatedAt: .now), for: scope)
            return (content, true)
        } catch {
            return (insights.fallback, false)
        }
    }

    private static func loadCache() -> [String: CachedReport] {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cache = try? JSONDecoder().decode([String: CachedReport].self, from: data)
        else { return [:] }
        return cache
    }

    private static func save(_ report: CachedReport, for scope: String) {
        var cache = loadCache()
        cache[scope] = report
        if cache.count > maximumCachedScopes {
            // Drop the oldest summaries first.
            for key in cache.sorted(by: { $0.value.generatedAt < $1.value.generatedAt }).prefix(cache.count - maximumCachedScopes).map(\.key) {
                cache[key] = nil
            }
        }
        if let data = try? JSONEncoder().encode(cache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

// MARK: - Facts and fallback

/// Last-7-days stats for one scope, plus the model facts and rule-based fallback derived from them.
struct WeeklyInsights {
    let current: InsightsStats
    let previous: InsightsStats
    let latest: DetectionEvent?
    let facts: String
    let fallback: HighlightContent

    /// - Parameter events: events already filtered to the scope, in any order.
    init(events: [DetectionEvent], sessions: [ScanSession], scopeName: String) {
        let weekStart = InsightsRange.week.startDate
        let previousStart = Calendar.current.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        current = InsightsStats(
            events: events.filter { $0.timestamp >= weekStart },
            sessions: sessions.filter { $0.startedAt >= weekStart }
        )
        previous = InsightsStats(
            events: events.filter { $0.timestamp >= previousStart && $0.timestamp < weekStart },
            sessions: sessions.filter { $0.startedAt >= previousStart && $0.startedAt < weekStart }
        )
        latest = events.max { $0.timestamp < $1.timestamp }
        facts = InsightDigest.facts(current: current, previous: previous, scope: scopeName, latest: latest)
        fallback = InsightDigest.fallback(current: current, previous: previous, latest: latest)
    }
}

enum InsightDigest {
    /// Compact, numbers-only briefing for the language model (kept well inside its context window).
    static func facts(current: InsightsStats, previous: InsightsStats, scope: String, latest: DetectionEvent?) -> String {
        var lines = [
            "Scope: \(scope), last 7 days.",
            "Scans logged: \(current.scanCount) across \(current.sessions.count) scanning sessions.",
            "Leaves detected: \(current.totalLeaves) (\(current.aphidLeaves) aphid-infested, \(current.healthyLeaves) healthy). Infestation rate \(current.infestationRate.percentText).",
        ]
        if previous.totalLeaves > 0 {
            lines.append("Previous 7 days infestation rate: \(previous.infestationRate.percentText).")
        }
        let days = current.trend.suffix(7).map { "\($0.date.formatted(.dateTime.month(.abbreviated).day())) \($0.rate.percentText)" }
        if !days.isEmpty {
            lines.append("Daily infestation rate: \(days.joined(separator: ", ")).")
        }
        let severities = current.severityCounts.filter { $0.count > 0 }.map { "\($0.severity.title.lowercased()) \($0.count)" }
        if !severities.isEmpty {
            lines.append("Scans by severity: \(severities.joined(separator: ", ")).")
        }
        let fields = current.fieldRates.prefix(4).map { "\($0.field) \($0.rate.percentText) of \($0.total) leaves" }
        if fields.count > 1 {
            lines.append("Infestation by field: \(fields.joined(separator: "; ")).")
        }
        if let latest, let severity = latest.severity {
            lines.append("Latest scan: \(severity.title.lowercased()) in \(latest.fieldName.isEmpty ? "an unnamed field" : latest.fieldName) on \(latest.timestamp.formatted(.dateTime.month(.abbreviated).day())).")
        }
        let validation = current.validation
        if validation.total > 0, let precision = validation.precision, let recall = validation.recall {
            lines.append("Field-verified detections: \(validation.total), precision \(precision.percentText), recall \(recall.percentText).")
        }
        return lines.joined(separator: "\n")
    }

    /// Deterministic highlights for devices without Apple Intelligence.
    static func fallback(current: InsightsStats, previous: InsightsStats, latest: DetectionEvent?) -> HighlightContent {
        var observations: [String] = []
        let headline: String

        if previous.totalLeaves > 0 {
            let change = (current.infestationRate - previous.infestationRate) * 100
            if abs(change) < 3 {
                headline = "Infestation is holding steady"
                observations.append("About \(current.infestationRate.percentText) of leaves were infested, similar to the week before.")
            } else if change > 0 {
                headline = "Aphid damage is rising"
                observations.append("Infestation rose from \(previous.infestationRate.percentText) to \(current.infestationRate.percentText) compared with the previous week.")
            } else {
                headline = "Aphid damage is easing"
                observations.append("Infestation fell from \(previous.infestationRate.percentText) to \(current.infestationRate.percentText) compared with the previous week.")
            }
        } else {
            headline = current.aphidLeaves == 0 ? "No aphid damage found" : "\(current.infestationRate.percentText) of leaves show aphid damage"
            observations.append("\(current.aphidLeaves) of \(current.totalLeaves) detected leaves were aphid-infested this week.")
        }

        if current.fieldRates.count > 1, let worst = current.fieldRates.first, worst.aphid > 0 {
            observations.append("\(worst.field) has the highest infestation at \(worst.rate.percentText).")
        }
        if let latest, let severity = latest.severity {
            observations.append("The latest scan in \(latest.fieldName.isEmpty ? "your field" : latest.fieldName) was \(severity.title.lowercased()), \(latest.timestamp.formatted(.relative(presentation: .named))).")
        }

        return HighlightContent(
            headline: headline,
            observations: Array(observations.prefix(3)),
            recommendation: current.overallSeverity?.recommendations.first
        )
    }
}
