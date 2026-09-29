//
//  PerformanceMonitorView.swift
//  Pepper Watch
//
//  Phone counterpart of the thesis "System Health Monitor" and FPS unit testing.
//

import Charts
import SwiftData
import SwiftUI

struct PerformanceMonitorView: View {
    @Environment(ScanModel.self) private var scanner
    @Environment(DeviceMonitor.self) private var monitor
    @Query(sort: \ScanSession.startedAt, order: .reverse) private var sessions: [ScanSession]
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    StatTile(title: "Thermal state", value: monitor.snapshot.thermalState.title, detail: "Throttles above Serious", symbol: monitor.snapshot.thermalState.symbol)
                    StatTile(title: "Memory footprint", value: "\(monitor.snapshot.memoryMB.fixed(0)) MB", detail: "App physical footprint", symbol: "memorychip")
                    StatTile(
                        title: "Battery",
                        value: monitor.snapshot.batteryPercent < 0 ? "—" : "\(monitor.snapshot.batteryPercent.fixed(0))%",
                        detail: "Field endurance",
                        symbol: "battery.75percent"
                    )
                    StatTile(title: "Last FPS", value: scanner.fps.fixed(1), detail: "\(scanner.inferenceMs.fixed(1)) ms per inference", symbol: "speedometer")
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            Section {
                if scanner.performanceSamples.isEmpty {
                    Text("Open the Scan tab to collect live FPS and latency samples. The most recent run is kept here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    liveFPSChart
                    liveLatencyChart
                }
            } header: {
                Text("Latest Scanning Run")
            } footer: {
                Text("Throughput counts analyzed frames per second. Frames that arrive during an inference are skipped rather than queued.")
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
            } footer: {
                Text("A session meets the real-time requirement when its average throughput reaches \(fpsTarget.fixed(0)) FPS.")
            }
        }
        .navigationTitle("Performance")
        .navigationBarTitleDisplayMode(.inline)
        .task { await monitor.monitor() }
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
