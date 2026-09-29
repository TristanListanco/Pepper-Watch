//
//  ScanInsight.swift
//  Pepper Watch
//
//  Plain-language insight about one scan photo:
//  1. Apple Intelligence with vision looks at the photo itself plus the detections.
//  2. Apple Intelligence without vision writes from the detections and color analysis.
//  3. Without Apple Intelligence, a rule-based summary of the same measurements.
//

import CoreGraphics
import Foundation
import FoundationModels

nonisolated enum ScanInsightSource: String, Sendable {
    case vision
    case text
    case standard

    var footnote: String {
        switch self {
        case .vision: "Apple Intelligence looked at this photo on device."
        case .text: "Written by Apple Intelligence on device from the detections."
        case .standard: "Standard analysis of the detections and leaf colors."
        }
    }
}

struct ScanInsight: Equatable {
    var headline: String
    var observations: [String]
    var nextStep: String?
    var source: ScanInsightSource
}

@Generable
nonisolated struct ScanImageReport {
    @Guide(description: "A short headline about what this scan shows, at most 10 words")
    var headline: String

    @Guide(description: "One to three short observations about the leaves, citing the numbers provided", .count(1...3))
    var observations: [String]

    @Guide(description: "One practical, low-risk next step for the farmer in a single sentence")
    var nextStep: String
}

/// Measurements taken from the photo and its detections, used as model facts and for the fallback.
nonisolated struct ScanImageFeatures: Sendable {
    var yellowedShare: Double?
    var infestedYellowedShare: Double?
    var largestInfestedArea: Double?
    var largestInfestedConfidence: Double?
    var infestedRegion: String?
    var meanConfidence: Double?

    static func analyze(_ image: CGImage?, detections: [Detection]) -> ScanImageFeatures {
        var features = ScanImageFeatures()
        let infested = detections.filter { $0.leafClass == .aphidInfested }
        if let largest = infested.max(by: { $0.rect.width * $0.rect.height < $1.rect.width * $1.rect.height }) {
            features.largestInfestedArea = largest.rect.width * largest.rect.height
            features.largestInfestedConfidence = largest.confidence
        }
        if !infested.isEmpty {
            let x = infested.reduce(0) { $0 + $1.rect.midX } / Double(infested.count)
            let y = infested.reduce(0) { $0 + $1.rect.midY } / Double(infested.count)
            let vertical = y < 0.34 ? "upper" : (y > 0.66 ? "lower" : "middle")
            let horizontal = x < 0.34 ? "left" : (x > 0.66 ? "right" : "center")
            features.infestedRegion = vertical == "middle" && horizontal == "center" ? "center" : "\(vertical) \(horizontal)"
        }
        if !detections.isEmpty {
            features.meanConfidence = detections.reduce(0) { $0 + $1.confidence } / Double(detections.count)
        }
        if let image, let colors = LeafColorSample(image: image) {
            features.yellowedShare = colors.yellowedShare(in: detections.map(\.rect))
            features.infestedYellowedShare = colors.yellowedShare(in: infested.map(\.rect))
        }
        return features
    }
}

/// A small RGB sample of the photo for rough leaf-color measurements.
private nonisolated struct LeafColorSample {
    private static let side = 96
    private var pixels: [UInt8]

    init?(image: CGImage) {
        let side = Self.side
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = buffer.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        pixels = buffer
    }

    /// Share of leaf-colored pixels inside the regions whose hue leans yellow (a rough chlorosis signal).
    func yellowedShare(in regions: [CGRect]) -> Double? {
        guard !regions.isEmpty else { return nil }
        var leaf = 0
        var yellowed = 0
        for row in 0..<Self.side {
            for column in 0..<Self.side {
                // Bitmap rows run bottom-up; detection rects are top-left normalized.
                let point = CGPoint(x: (Double(column) + 0.5) / Double(Self.side), y: 1 - (Double(row) + 0.5) / Double(Self.side))
                guard regions.contains(where: { $0.contains(point) }) else { continue }
                let index = (row * Self.side + column) * 4
                let (hue, saturation, brightness) = Self.hsb(pixels[index], pixels[index + 1], pixels[index + 2])
                guard saturation > 0.2, brightness > 0.2, (0.1...0.45).contains(hue) else { continue }
                leaf += 1
                if hue < 0.19 { yellowed += 1 }
            }
        }
        return leaf < 20 ? nil : Double(yellowed) / Double(leaf)
    }

    private static func hsb(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (Double, Double, Double) {
        let red = Double(r) / 255, green = Double(g) / 255, blue = Double(b) / 255
        let maximum = max(red, green, blue), minimum = min(red, green, blue), delta = maximum - minimum
        guard delta > 0 else { return (0, 0, maximum) }
        var hue: Double
        if maximum == red { hue = (green - blue) / delta }
        else if maximum == green { hue = 2 + (blue - red) / delta }
        else { hue = 4 + (red - green) / delta }
        hue /= 6
        if hue < 0 { hue += 1 }
        return (hue, delta / maximum, maximum)
    }
}

enum ScanInsightGenerator {
    private static let instructions = """
    You are the scouting assistant in Pepper Watch, an offline app that detects aphid damage on bell pepper \
    leaves. Explain what one scan shows for a smallholder farmer. The detections come from an on-device model; \
    keep your numbers consistent with them. If a photo is attached, mention visible signs such as aphid \
    colonies, yellowing, curling, honeydew or sooty mold only when you can actually see them. Write plain, \
    short sentences. Suggest only low-risk integrated pest management steps and never name chemical \
    pesticides or doses.
    """

    static func generate(image: CGImage?, detections: [Detection], fieldName: String, date: Date) async -> ScanInsight {
        let summary = DetectionSummary(detections)
        let features = await measure(image, detections: detections)
        let facts = self.facts(summary: summary, features: features, detections: detections, fieldName: fieldName, date: date)

        let model = SystemLanguageModel.default
        if model.availability == .available {
            let session = LanguageModelSession(instructions: instructions)
            do {
                if let image, model.capabilities.contains(.vision) {
                    let response = try await session.respond(generating: ScanImageReport.self) {
                        facts
                        Attachment(image).label("Scan photo")
                    }
                    return ScanInsight(response.content, source: .vision)
                }
                let response = try await session.respond(to: facts, generating: ScanImageReport.self)
                return ScanInsight(response.content, source: .text)
            } catch {
                // Fall back to the standard analysis below.
            }
        }
        return fallback(summary: summary, features: features)
    }

    @concurrent private static func measure(_ image: CGImage?, detections: [Detection]) async -> ScanImageFeatures {
        ScanImageFeatures.analyze(image, detections: detections)
    }

    private static func facts(summary: DetectionSummary, features: ScanImageFeatures, detections: [Detection], fieldName: String, date: Date) -> String {
        var lines = [
            "Field: \(fieldName.isEmpty ? "unnamed" : fieldName). Scan taken \(date.formatted(date: .abbreviated, time: .shortened)).",
            "Detections: \(summary.aphidCount) aphid-infested and \(summary.healthyCount) healthy leaves (\(summary.infestationRate.percentText) infested, severity \(summary.severity?.title.lowercased() ?? "none")).",
        ]
        let infestedConfidences = detections.filter { $0.leafClass == .aphidInfested }.map { $0.confidence.percentText }
        if !infestedConfidences.isEmpty {
            lines.append("Infested leaf confidences: \(infestedConfidences.joined(separator: ", ")).")
        }
        if let area = features.largestInfestedArea {
            lines.append("The largest infested leaf covers \(area.percentText) of the photo.")
        }
        if let region = features.infestedRegion {
            lines.append("Infested leaves are mostly in the \(region) of the photo.")
        }
        if let yellowed = features.yellowedShare {
            lines.append("Color analysis: \(yellowed.percentText) of leaf pixels look yellowed\(features.infestedYellowedShare.map { " (\($0.percentText) within infested leaves)" } ?? "").")
        }
        return lines.joined(separator: "\n")
    }

    private static func fallback(summary: DetectionSummary, features: ScanImageFeatures) -> ScanInsight {
        guard let severity = summary.severity else {
            return ScanInsight(
                headline: "No leaves detected in this photo",
                observations: ["Try a closer, well-lit photo of the leaves, including their undersides."],
                nextStep: nil,
                source: .standard
            )
        }
        var observations: [String] = []
        if let area = features.largestInfestedArea, let confidence = features.largestInfestedConfidence {
            observations.append("The largest damaged leaf covers \(area.percentText) of the frame (\(confidence.percentText) confidence).")
        }
        if let region = features.infestedRegion, summary.aphidCount > 1 {
            observations.append("Damage is concentrated in the \(region) of the photo.")
        }
        if let yellowed = features.yellowedShare, yellowed >= 0.1 {
            observations.append("About \(yellowed.percentText) of leaf area looks yellowed, a possible sign of chlorosis.")
        } else if summary.aphidCount == 0 {
            observations.append("Leaf color looks even, with little yellowing.")
        }
        if observations.isEmpty, let confidence = features.meanConfidence {
            observations.append("Detections average \(confidence.percentText) confidence.")
        }
        return ScanInsight(
            headline: summary.aphidCount == 0
                ? "No aphid damage in this photo"
                : "\(summary.aphidCount) of \(summary.totalLeaves) leaves show aphid damage",
            observations: Array(observations.prefix(3)),
            nextStep: severity.recommendations.first,
            source: .standard
        )
    }
}

private extension ScanInsight {
    init(_ report: ScanImageReport, source: ScanInsightSource) {
        self.init(headline: report.headline, observations: report.observations, nextStep: report.nextStep, source: source)
    }
}

extension DetectionEvent {
    var savedInsight: ScanInsight? {
        guard let insightHeadline else { return nil }
        return ScanInsight(
            headline: insightHeadline,
            observations: insightObservations ?? [],
            nextStep: insightNextStep,
            source: insightSourceRaw.flatMap(ScanInsightSource.init(rawValue:)) ?? .standard
        )
    }

    func save(_ insight: ScanInsight) {
        insightHeadline = insight.headline
        insightObservations = insight.observations
        insightNextStep = insight.nextStep
        insightSourceRaw = insight.source.rawValue
        insightGeneratedAt = .now
    }
}
