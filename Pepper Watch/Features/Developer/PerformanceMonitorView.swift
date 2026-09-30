//
//  PerformanceMonitorView.swift
//  Pepper Watch
//
//  Phone counterpart of the thesis "System Health Monitor" and FPS unit testing.
//

import Charts
import CoreML
import SwiftData
import SwiftUI

struct PerformanceMonitorView: View {
    @Environment(ScanModel.self) private var scanner
    @Environment(DeviceMonitor.self) private var monitor
    @Environment(DetectionEngine.self) private var engine
    @Environment(LocationProvider.self) private var location
    @Environment(MetricsCollector.self) private var metrics
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(sort: \ScanSession.startedAt, order: .reverse) private var sessions: [ScanSession]
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0

    var body: some View {
        List {
            Section {
                statTiles
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                if scanner.performanceSamples.isEmpty {
                    Text("Open the Scan tab to collect live FPS and latency samples. The most recent run is kept here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if horizontalSizeClass == .regular {
                    HStack(alignment: .top, spacing: 24) {
                        liveFPSChart
                        liveLatencyChart
                    }
                } else {
                    liveFPSChart
                    liveLatencyChart
                }
            } header: {
                Text("Latest Scanning Run")
            }

            Section("Memory") {
                Chart(monitor.memoryHistory) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("MB", sample.megabytes))
                        .foregroundStyle(.tint)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis(.hidden)
                .frame(height: 120)
            }

            dailyMetricsSection
            resourcePlanSection
            locationSection

            Section {
                if sessions.isEmpty {
                    Text("No scanning sessions recorded yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sessions.prefix(30)) { session in
                    SessionRow(session: session, target: fpsTarget)
                }
            } header: {
                Text("Session History")
            }
        }
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
        .task { await monitor.monitor() }
    }

    // MARK: - Tiles

    /// Four equal tiles spanning the width: one row on iPad, two on iPhone. A lazy grid, because a
    /// `Grid` of height-filling tiles keeps a self-sizing list row relaying out.
    private var statTiles: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: horizontalSizeClass == .regular ? 4 : 2)
        return LazyVGrid(columns: columns, spacing: 12) {
            throughputTile
            thermalTile
            memoryTile
            batteryTile
        }
    }

    private var throughputTile: some View {
        // `sessions` is already newest first; no second query needed.
        let reading = ThroughputReading.current(scanner: scanner, lastSession: sessions.first { ThroughputReading.isMeasured($0) })
        return StatTile(
            title: "Throughput",
            value: reading.map { "\($0.fps.fixed(1)) FPS" } ?? "—",
            detail: reading.map { "\($0.isLive ? "Live" : "Last scan") · \($0.inferenceMs.fixed(1)) ms" } ?? "No scans yet",
            symbol: "speedometer"
        )
    }

    private var thermalTile: some View {
        StatTile(title: "Thermal state", value: monitor.snapshot.thermalState.title, detail: "Scanning eases off at Serious", symbol: monitor.snapshot.thermalState.symbol)
    }

    private var memoryTile: some View {
        StatTile(title: "Memory", value: "\(monitor.snapshot.memoryMB.fixed(0)) MB", detail: "App footprint", symbol: "memorychip")
    }

    private var batteryTile: some View {
        StatTile(
            title: "Battery",
            value: monitor.snapshot.batteryPercent < 0 ? "—" : "\(monitor.snapshot.batteryPercent.fixed(0))%",
            detail: "Field endurance",
            symbol: "battery.75percent"
        )
    }

    // MARK: - Resources

    /// What scanning would use right now: the scanner's live plan while it runs.
    private var currentPlan: ResourcePlan {
        if scanner.status == .running { return scanner.resourcePlan }
        let hasNeuralEngine = MLComputeDevice.allComputeDevices.contains { if case .neuralEngine = $0 { true } else { false } }
        return ResourcePlan.current(
            allowsPipelining: AppSettings.pipelinedInference && hasNeuralEngine && engine.activeComputeUnits != .cpuOnly,
            lensCheck: AppSettings.lensSmudgeCheck
        )
    }

    private var resourcePlanSection: some View {
        let plan = currentPlan
        return Section {
            LabeledContent("Mode", value: plan.mode.title)
            LabeledContent("Camera", value: plan.cameraFrameRate.map { "\($0) FPS cap" } ?? "Default rate")
            LabeledContent("Frames in flight", value: "\(plan.framesInFlight)")
            LabeledContent("Lens check", value: plan.checksLens ? "On" : "Paused")
        } header: {
            Text("Resource Plan")
        }
    }

    private var locationSection: some View {
        let received = location.updatesReceived
        let published = location.updatesPublished
        return Section {
            LabeledContent("Status", value: location.isRunning ? "Streaming" : "Off")
            LabeledContent("Precise Location", value: location.isAccuracyLimited ? "Off" : "On")
            LabeledContent("Updates used", value: received == 0 ? "—" : "\(published) of \(received)")
        } header: {
            Text("Location")
        }
    }

    private var dailyMetricsSection: some View {
        Section {
            if let summary = metrics.latest {
                LabeledContent("Period", value: (summary.start..<summary.end).formatted(.interval.month(.abbreviated).day().hour()))
                usageRow("Time on screen", summary.day.foregroundSeconds, scanning: summary.scanning?.foregroundSeconds, unit: .duration)
                usageRow("CPU time", summary.day.cpuSeconds, scanning: summary.scanning?.cpuSeconds, unit: .duration)
                usageRow("GPU time", summary.day.gpuSeconds, scanning: summary.scanning?.gpuSeconds, unit: .duration)
                usageRow("Peak memory", summary.day.peakMemoryMB, scanning: summary.scanning?.peakMemoryMB, unit: .megabytes)
                usageRow("Hangs", summary.day.hangSeconds, scanning: summary.scanning?.hangSeconds, unit: .duration)
                usageRow("Precise location", summary.day.preciseLocationSeconds, scanning: summary.scanning?.preciseLocationSeconds, unit: .duration)
                usageRow("Coarse location", summary.day.coarseLocationSeconds, scanning: summary.scanning?.coarseLocationSeconds, unit: .duration)
            } else {
                Text("MetricKit sends a report about once a day on a device. The first one shows up here the day after you scan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if metrics.diagnosticsReceived > 0 {
                LabeledContent("Diagnostics", value: "\(metrics.diagnosticsReceived) this launch")
            }
        } header: {
            Text("Daily Metrics")
        }
    }

    private enum UsageUnit { case duration, megabytes }

    @ViewBuilder
    private func usageRow(_ title: String, _ total: Double?, scanning: Double?, unit: UsageUnit) -> some View {
        if let total {
            let text = format(total, unit)
            LabeledContent(title, value: scanning.map { "\(text) · \(format($0, unit)) scanning" } ?? text)
        }
    }

    private func format(_ value: Double, _ unit: UsageUnit) -> String {
        switch unit {
        case .megabytes:
            return "\(value.fixed(0)) MB"
        case .duration:
            return Duration.seconds(value).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2))
        }
    }

    private var liveFPSChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Throughput (FPS)").font(.subheadline.weight(.semibold))
            Chart {
                RuleMark(y: .value("Target", fpsTarget))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("Target \(fpsTarget.fixed(0))").font(.caption2).foregroundStyle(.secondary)
                    }
                ForEach(scanner.performanceSamples) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("FPS", sample.fps))
                        .foregroundStyle(.tint)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0...max(fpsTarget * 2, (scanner.performanceSamples.map(\.fps).max() ?? 0) * 1.1))
            .chartXAxis(.hidden)
            .frame(height: 140)
        }
        .padding(.vertical, 4)
    }

    private var liveLatencyChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Inference latency (ms)").font(.subheadline.weight(.semibold))
            Chart(scanner.performanceSamples) { sample in
                AreaMark(x: .value("Time", sample.date), y: .value("ms", sample.latencyMs))
                    .foregroundStyle(.tint.opacity(0.2))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Time", sample.date), y: .value("ms", sample.latencyMs))
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
            .chartXAxis(.hidden)
            .frame(height: 120)
        }
        .padding(.vertical, 4)
    }
}

/// Throughput and latency to show at a glance: live while scanning, otherwise the last real scan's averages.
struct ThroughputReading {
    var fps: Double
    var inferenceMs: Double
    var isLive: Bool

    /// The most recent finished scan that analyzed frames; demo sessions don't count.
    static var lastSession: FetchDescriptor<ScanSession> {
        var descriptor = FetchDescriptor<ScanSession>(
            predicate: #Predicate { $0.endedAt != nil && !$0.isDemo && $0.framesProcessed > 0 },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    /// The same test as `lastSession`, for sessions already fetched.
    static func isMeasured(_ session: ScanSession) -> Bool {
        session.endedAt != nil && !session.isDemo && session.framesProcessed > 0
    }

    static func current(scanner: ScanModel, lastSession: ScanSession?) -> ThroughputReading? {
        if scanner.status == .running, scanner.fps > 0 {
            return ThroughputReading(fps: scanner.fps, inferenceMs: scanner.inferenceMs, isLive: true)
        }
        return lastSession.map { ThroughputReading(fps: $0.averageFPS, inferenceMs: $0.averageInferenceMs, isLive: false) }
    }
}

private struct SessionRow: View {
    let session: ScanSession
    let target: Double

    var body: some View {
        let passes = session.averageFPS >= target
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.fieldName.isEmpty ? "Session" : session.fieldName)
                    .font(.subheadline.weight(.semibold))
                Text(session.startedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(session.framesProcessed.formatted()) frames · \(session.averageInferenceMs.fixed(1)) ms · \(session.computeUnits)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("\(session.averageFPS.fixed(1)) FPS", systemImage: passes ? Severity.clear.symbol : Severity.severe.symbol)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(passes ? Severity.clear.color : Severity.severe.color)
                .accessibilityLabel("\(session.averageFPS.fixed(1)) frames per second, \(passes ? "meets" : "below") target")
        }
    }
}
