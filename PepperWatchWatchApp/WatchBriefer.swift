//
//  WatchBriefer.swift
//  Pepper Watch (Apple Watch)
//
//  Apple Intelligence on the watch. watchOS runs Foundation Models through Private Cloud
//  Compute, so a brief is made only when you ask for one. Only the numbers below are sent, never images.
//

import Foundation
import FoundationModels
import Observation
import WidgetKit

@Generable
nonisolated struct GeneratedBrief {
    @Guide(description: "A glanceable headline about the aphid situation, at most 7 words")
    var headline: String

    @Guide(description: "One practical, low-risk step for today, at most 12 words, starting with a verb")
    var action: String
}

@Observable
final class WatchBriefer {
    enum Phase: Equatable {
        case idle
        case generating
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private let model = PrivateCloudComputeLanguageModel()

    private static let instructions = """
    You write a two-line Apple Watch briefing for a bell pepper farmer in Northern Mindanao, Philippines, \
    who scans leaves for aphid damage. Use only the numbers given and never invent data. Consider how long \
    ago the last scan was: if it was more than two days ago, suggest scanning again. Suggest only low-risk \
    integrated pest management steps, such as checking leaf undersides, removing infested leaves, spraying \
    water, insecticidal soap or neem oil according to the label, or re-scanning. Never name chemical pesticides.
    """

    var isAvailable: Bool { model.isAvailable }

    /// The saved brief for this scope while the numbers haven't changed.
    func brief(for status: WidgetSnapshot.FieldStatus) -> WatchBrief? {
        WatchStore.brief(for: status.id, facts: ScopeStats(status).facts(for: status))
    }

    func generate(for status: WidgetSnapshot.FieldStatus) async {
        guard phase != .generating else { return }
        let facts = ScopeStats(status).facts(for: status)
        phase = .generating
        do {
            let session = LanguageModelSession(model: model, instructions: Self.instructions)
            let prompt = "\(facts)\nNow: \(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour()))."
            let response = try await session.respond(to: prompt, generating: GeneratedBrief.self)
            let brief = WatchBrief(headline: response.content.headline, action: response.content.action, facts: facts, generatedAt: .now)
            WatchStore.saveBrief(brief, for: status.id)
            WidgetCenter.shared.reloadAllTimelines()
            phase = .idle
        } catch {
            phase = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        switch error as? PrivateCloudComputeLanguageModel.Error {
        case .quotaLimitReached?: "Daily limit reached. Try again later."
        case .networkFailure?: "Connect to Wi-Fi or your iPhone to make a brief."
        default: "Couldn't make a brief right now."
        }
    }
}
