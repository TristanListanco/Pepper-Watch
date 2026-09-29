//
//  InsightsStats.swift
//  Pepper Watch
//

import CoreLocation
import Foundation

/// Field-validation confusion matrix for the positive class `aphid_infested`,
/// using the thesis definitions (Section 4.10): TP = infested confirmed, FP = healthy leaf
/// flagged as infested, TN = healthy confirmed, FN = infested leaf predicted healthy.
struct ValidationMetrics: Equatable {
    var truePositives = 0
    var falsePositives = 0
    var trueNegatives = 0
    var falseNegatives = 0

    var total: Int { truePositives + falsePositives + trueNegatives + falseNegatives }

    /// Eq. 1 — TP / (TP + FP)
    var precision: Double? { ratio(truePositives, truePositives + falsePositives) }
    /// Eq. 2 — TP / (TP + FN)
    var recall: Double? { ratio(truePositives, truePositives + falseNegatives) }
    /// Eq. 3 — (TP + TN) / (TP + TN + FP + FN)
    var accuracy: Double? { ratio(truePositives + trueNegatives, total) }
    /// Eq. 4 — 2 × P × R / (P + R)
    var f1: Double? {
        guard let precision, let recall, precision + recall > 0 else { return nil }
        return 2 * precision * recall / (precision + recall)
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double? {
        denominator == 0 ? nil : Double(numerator) / Double(denominator)
    }

    mutating func add(predicted: LeafClass, verdict: Verdict) {
        switch (predicted, verdict) {
        case (.aphidInfested, .correct): truePositives += 1
        case (.aphidInfested, .incorrect): falsePositives += 1
        case (.healthy, .correct): trueNegatives += 1
        case (.healthy, .incorrect): falseNegatives += 1
        }
    }
}

struct InsightsStats {
    struct DailyPoint: Identifiable {
        var id: Date { day }
        let day: Date
        var aphid = 0
        var healthy = 0
        var scans = 0
        var total: Int { aphid + healthy }
        var rate: Double { total == 0 ? 0 : Double(aphid) / Double(total) }
    }

    struct DailyClassCount: Identifiable {
        var id: String { "\(day.timeIntervalSince1970)-\(leafClass.rawValue)" }
        let day: Date
        let leafClass: LeafClass
        let count: Int
    }

    struct SeverityCount: Identifiable {
        var id: Severity { severity }
        let severity: Severity
        let count: Int
    }

    struct ConfidenceBin: Identifiable {
        var id: String { "\(leafClass.rawValue)-\(lowerBound)" }
        let leafClass: LeafClass
        let lowerBound: Double
        let count: Int
        var label: String { "\(Int((lowerBound * 100).rounded()))–\(Int(((lowerBound + 0.1) * 100).rounded()))%" }
    }

    struct FieldRate: Identifiable {
        var id: String { field }
        let field: String
        let aphid: Int
        let total: Int
        var rate: Double { total == 0 ? 0 : Double(aphid) / Double(total) }
    }

    struct SessionPerformance: Identifiable {
        let id: UUID
        let date: Date
        let field: String
        let fps: Double
        let latencyMs: Double
        let computeUnits: String
    }

    struct MapPoint: Identifiable {
        let id: UUID
        let coordinate: CLLocationCoordinate2D
        let severity: Severity?
        let summary: DetectionSummary
        let date: Date
        let field: String
    }

    var scanCount = 0
    var aphidLeaves = 0
    var healthyLeaves = 0
    var latestSeverity: Severity?
    var averageInferenceMs: Double = 0
    var daily: [DailyPoint] = []
    var dailyClassCounts: [DailyClassCount] = []
    var severityCounts: [SeverityCount] = []
    var confidenceBins: [ConfidenceBin] = []
    var fieldRates: [FieldRate] = []
    var sessions: [SessionPerformance] = []
    var mapPoints: [MapPoint] = []
    var validation = ValidationMetrics()

    var totalLeaves: Int { aphidLeaves + healthyLeaves }
    var infestationRate: Double { totalLeaves == 0 ? 0 : Double(aphidLeaves) / Double(totalLeaves) }
    var overallSeverity: Severity? { DetectionSummary(aphidCount: aphidLeaves, healthyCount: healthyLeaves).severity }

    init(events: [DetectionEvent], sessions: [ScanSession], calendar: Calendar = .current) {
        scanCount = events.count
        latestSeverity = events.max(by: { $0.timestamp < $1.timestamp })?.severity

        var byDay: [Date: DailyPoint] = [:]
        var bySeverity: [Severity: Int] = [:]
        var byField: [String: (aphid: Int, total: Int)] = [:]
        var bins: [LeafClass: [Int: Int]] = [:]
        var inferenceTotal = 0.0

        for event in events {
            aphidLeaves += event.aphidCount
            healthyLeaves += event.healthyCount
            inferenceTotal += event.inferenceMs

            let day = calendar.startOfDay(for: event.timestamp)
            var point = byDay[day] ?? DailyPoint(day: day)
            point.aphid += event.aphidCount
            point.healthy += event.healthyCount
            point.scans += 1
            byDay[day] = point

            if let severity = event.severity { bySeverity[severity, default: 0] += 1 }

            let field = event.fieldName.isEmpty ? "Unnamed" : event.fieldName
            byField[field, default: (0, 0)].aphid += event.aphidCount
            byField[field, default: (0, 0)].total += event.aphidCount + event.healthyCount

            for box in event.boxes {
                let bin = min(Int(box.confidence * 10), 9)
                bins[box.leafClass, default: [:]][bin, default: 0] += 1
                if let verdict = box.verdict {
                    validation.add(predicted: box.leafClass, verdict: verdict)
                }
            }

            if let coordinate = event.coordinate {
                mapPoints.append(MapPoint(
                    id: event.id,
                    coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                    severity: event.severity,
                    summary: event.summary,
                    date: event.timestamp,
                    field: field
                ))
            }
        }

        averageInferenceMs = events.isEmpty ? 0 : inferenceTotal / Double(events.count)
        daily = byDay.values.sorted { $0.day < $1.day }
        dailyClassCounts = daily.flatMap { point in
            [
                DailyClassCount(day: point.day, leafClass: .aphidInfested, count: point.aphid),
                DailyClassCount(day: point.day, leafClass: .healthy, count: point.healthy),
            ]
        }
        severityCounts = Severity.allCases.map { SeverityCount(severity: $0, count: bySeverity[$0] ?? 0) }
        fieldRates = byField.map { FieldRate(field: $0.key, aphid: $0.value.aphid, total: $0.value.total) }
            .sorted { $0.rate > $1.rate }

        // Start at the model's default 0.25 floor unless a lower threshold produced detections.
        let lowestBin = min(2, bins.values.flatMap(\.keys).min() ?? 2)
        confidenceBins = LeafClass.allCases.flatMap { leafClass in
            (lowestBin...9).map { bin in
                ConfidenceBin(leafClass: leafClass, lowerBound: Double(bin) / 10, count: bins[leafClass]?[bin] ?? 0)
            }
        }

        self.sessions = sessions
            .filter { $0.framesProcessed > 0 && $0.averageFPS > 0 }
            .sorted { $0.startedAt < $1.startedAt }
            .map {
                SessionPerformance(
                    id: $0.id, date: $0.startedAt, field: $0.fieldName,
                    fps: $0.averageFPS, latencyMs: $0.averageInferenceMs, computeUnits: $0.computeUnits
                )
            }
    }
}
