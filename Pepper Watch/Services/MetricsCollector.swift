//
//  MetricsCollector.swift
//  Pepper Watch
//
//  Daily resource reports from MetricKit (iOS 27 Swift API). The system delivers them about
//  once a day on a device; each is summarized, kept for the Performance screen and logged.
//

import Foundation
import MetricKit
import Observation
import StateReporting

/// What the app used over one MetricKit report, overall and while scanning.
nonisolated struct MetricsSummary: Codable, Sendable, Equatable {
    struct Usage: Codable, Sendable, Equatable {
        var foregroundSeconds: Double?
        var cpuSeconds: Double?
        var gpuSeconds: Double?
        var peakMemoryMB: Double?
        /// Approximate time the app hung, from the hang histogram.
        var hangSeconds: Double?
        /// Location at 10 m or better, the power-hungry kind.
        var preciseLocationSeconds: Double?
        /// Location at 100 m or coarser.
        var coarseLocationSeconds: Double?

        init(_ values: [MetricResult]) {
            for value in values {
                switch value {
                case .totalForegroundTime(let metric):
                    foregroundSeconds = (foregroundSeconds ?? 0) + metric.value.converted(to: .seconds).value
                case .cpuTime(let metric):
                    cpuSeconds = (cpuSeconds ?? 0) + metric.value.converted(to: .seconds).value
                case .gpuTime(let metric):
                    gpuSeconds = (gpuSeconds ?? 0) + metric.value.converted(to: .seconds).value
                case .peakMemory(let metric):
                    peakMemoryMB = max(peakMemoryMB ?? 0, metric.value.converted(to: .megabytes).value)
                case .hangTime(let metric):
                    let seconds = metric.histogram.buckets.reduce(0.0) { total, bucket in
                        let middle = (bucket.lowerBound.converted(to: .seconds).value + bucket.upperBound.converted(to: .seconds).value) / 2
                        return total + middle * Double(bucket.count)
                    }
                    hangSeconds = (hangSeconds ?? 0) + seconds
                case .locationActivityTime(let metric):
                    let precise = [metric.bestAccuracyForNavigation, metric.bestAccuracy, metric.tenMeters]
                    let coarse = [metric.oneHundredMeter, metric.oneKilometer, metric.threeKilometers, metric.reducedAccuracy]
                    preciseLocationSeconds = (preciseLocationSeconds ?? 0) + precise.reduce(0) { $0 + $1.converted(to: .seconds).value }
                    coarseLocationSeconds = (coarseLocationSeconds ?? 0) + coarse.reduce(0) { $0 + $1.converted(to: .seconds).value }
                default:
                    break
                }
            }
        }
    }

    var start: Date
    var end: Date
    var day: Usage
    /// Only the time the app reported it was scanning.
    var scanning: Usage?
    var lowPowerMode: Bool?

    init(_ report: MetricReport) {
        start = report.timeRange.start
        end = report.timeRange.end
        day = Usage(report.intervalEntries.fullDayEntry.values)
        let scanningValues = report.stateEntries
            .filter { $0.state.domain == AppActivity.domain && $0.state.label == AppActivity.scanningLabel }
            .flatMap(\.values)
        scanning = scanningValues.isEmpty ? nil : Usage(scanningValues)
        lowPowerMode = report.environment?.lowPowerModeEnabled
    }
}

@Observable
final class MetricsCollector {
    private(set) var latest: MetricsSummary?
    private(set) var diagnosticsReceived = 0

    @ObservationIgnored private let logger: SystemLogger?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var manager: MetricManager?

    private static let storageKey = "metrics.latestSummary"

    init(logger: SystemLogger?) {
        self.logger = logger
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            latest = try? JSONDecoder().decode(MetricsSummary.self, from: data)
        }
    }

    /// Subscribes to MetricKit, with scanning broken out through the app's state reporting domain.
    func start() {
        guard manager == nil else { return }
        let manager = MetricManager(enabledStateReportingDomains: [StateReportingDomain(rawValue: AppActivity.domain)])
        self.manager = manager
        tasks = [
            Task { [weak self] in
                for await report in manager.metricReports {
                    self?.handle(report)
                }
            },
            Task { [weak self] in
                for await report in manager.diagnosticReports {
                    self?.handle(report)
                }
            },
        ]
    }

    private func handle(_ report: MetricReport) {
        let summary = MetricsSummary(report)
        latest = summary
        if let data = try? JSONEncoder().encode(summary) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        let cpu = summary.day.cpuSeconds.map { "\(Int($0)) s CPU" } ?? "no CPU data"
        let scanning = summary.scanning?.cpuSeconds.map { ", \(Int($0)) s while scanning" } ?? ""
        let memory = summary.day.peakMemoryMB.map { ", peak \(Int($0)) MB" } ?? ""
        logger?.log(category: "metrics", "Daily report: \(cpu)\(scanning)\(memory)")
    }

    private func handle(_ report: DiagnosticReport) {
        diagnosticsReceived += 1
        logger?.log(.warning, category: "metrics", "MetricKit diagnostic received (hang, crash or resource exception)")
    }
}
