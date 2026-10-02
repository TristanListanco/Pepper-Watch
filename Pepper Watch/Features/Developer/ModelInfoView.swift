//
//  ModelInfoView.swift
//  Pepper Watch
//

import Charts
import CoreML
import SwiftUI

struct ModelInfoView: View {
    @Environment(DetectionEngine.self) private var engine
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0
    @AppStorage("modelCard.precision") private var reportedPrecision = 0.0
    @AppStorage("modelCard.recall") private var reportedRecall = 0.0
    @AppStorage("modelCard.map50") private var reportedMAP50 = 0.0
    @AppStorage("modelCard.map5095") private var reportedMAP5095 = 0.0

    @State private var iterations = 50
    @State private var isBenchmarking = false
    @State private var benchmarkRuns = 0
    @State private var benchmark: DetectionEngine.BenchmarkResult?
    @State private var benchmarkError: String?
    @State private var computePlan: ComputePlanReport?
    @State private var computePlanError: String?

    var body: some View {
        List {
            if let info = engine.modelInfo {
                modelCard(info)
            } else {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading model…").foregroundStyle(.secondaryText)
                    }
                }
            }
            runtimeSection
            computePlanSection
            benchmarkSection
            trainingMetricsSection
        }
        .navigationTitle("Model Card")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func modelCard(_ info: ModelInfo) -> some View {
        Section {
            LabeledContent("File", value: "\(AphidDetector.modelName).mlpackage")
            LabeledContent("Task", value: info.task.capitalized)
            LabeledContent("Architecture", value: "Ultralytics YOLO + NMS pipeline")
            LabeledContent("Input", value: "\(info.inputWidth) × \(info.inputHeight) RGB")
            ForEach(Array(info.classNames.enumerated()), id: \.offset) { index, name in
                let leafClass = LeafClass(rawValue: name)
                LabeledContent {
                    Text(name).font(.body.monospaced())
                } label: {
                    Label("Class \(index)", systemImage: leafClass?.symbol ?? "tag")
                        .foregroundStyle((leafClass?.color ?? .secondary).legible)
                }
            }
            LabeledContent("Default confidence", value: info.defaultConfidence.map { $0.fixed(2) } ?? "—")
            LabeledContent("Default IoU", value: info.defaultIoU.map { $0.fixed(2) } ?? "—")
            LabeledContent("Size on disk", value: info.sizeOnDisk.formatted(.byteCount(style: .file)))
            LabeledContent("Exporter", value: "\(info.author) \(info.version)")
            LabeledContent("License", value: info.license)
            LabeledContent("Exported", value: info.exportedAt)
            // The full Ultralytics export command is long; it opens on demand.
            DisclosureGroup("Export arguments") {
                Text(info.exportArguments)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondaryText)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Model")
        }
    }

    private var runtimeSection: some View {
        Section("Runtime") {
            LabeledContent("Status", value: statusText)
            LabeledContent("Compute units", value: engine.activeComputeUnits?.title ?? "—")
            LabeledContent("Specialization", value: engine.activeOptions.map { $0.fastPrediction ? "Fast prediction" : "Default" } ?? "—")
            LabeledContent("Load time", value: engine.loadDuration.map { "\(($0 / .milliseconds(1)).fixed(0)) ms" } ?? "—")
            LabeledContent("Warm-up", value: engine.warmUpDuration.map { "\(($0 / .milliseconds(1)).fixed(0)) ms" } ?? "—")
            LabeledContent("Camera frames in flight", value: pipelineText)
            LabeledContent("Available devices", value: MLModel.availableComputeDevices.map { Self.describe($0) }.joined(separator: ", "))
            LabeledContent("Processing", value: "100% on-device")
        }
    }

    private var pipelineText: String {
        let hasNeuralEngine = MLModel.availableComputeDevices.contains { if case .neuralEngine = $0 { true } else { false } }
        guard AppSettings.pipelinedInference, hasNeuralEngine, engine.activeComputeUnits != .cpuOnly else { return "1" }
        return "Up to 2 while cool"
    }

    // MARK: - Compute plan

    private var computePlanSection: some View {
        Section {
            if let computePlan {
                Chart(ComputePlanReport.Device.allCases) { device in
                    BarMark(x: .value("Share of estimated cost", computePlan.costShare[device] ?? 0), y: .value("Model", "Detector"))
                        .foregroundStyle(by: .value("Device", device.rawValue))
                }
                .chartForegroundStyleScale([
                    ComputePlanReport.Device.neuralEngine.rawValue: Color.green,
                    ComputePlanReport.Device.gpu.rawValue: Color.blue,
                    ComputePlanReport.Device.cpu.rawValue: Color.gray,
                ])
                .chartXScale(domain: 0...1)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: 64)
                .accessibilityLabel("Estimated cost by device")

                ForEach(ComputePlanReport.Device.allCases) { device in
                    LabeledContent(device.rawValue, value: (computePlan.costShare[device] ?? 0).percentText)
                }
                LabeledContent("Operations", value: "\(computePlan.operationCount)")
                if !computePlan.fallbackOperators.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Not on the Neural Engine")
                        Text(computePlan.fallbackOperators.prefix(6).map { "\($0.name) ×\($0.count)" }.joined(separator: ", "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondaryText)
                    }
                }
            } else if let computePlanError {
                Label(computePlanError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondaryText)
            } else {
                HStack {
                    ProgressView()
                    Text("Analyzing…").foregroundStyle(.secondaryText)
                }
            }
        } header: {
            Text("Compute Plan")
        }
        .task(id: engine.activeOptions) {
            guard let options = engine.activeOptions else { return }
            do {
                computePlan = try await ComputePlanReport.load(options: options)
                computePlanError = nil
            } catch {
                computePlanError = error.localizedDescription
            }
        }
    }

    private var statusText: String {
        switch engine.state {
        case .idle: "Idle"
        case .loading: "Loading"
        case .ready: "Ready"
        case .failed(let message): message
        }
    }

    private static func describe(_ device: MLComputeDevice) -> String {
        switch device {
        case .cpu: "CPU"
        case .gpu: "GPU"
        case .neuralEngine(let engine): "Neural Engine (\(engine.totalCoreCount) cores)"
        @unknown default: "Other"
        }
    }

    // MARK: - Benchmark

    private var benchmarkSection: some View {
        Section {
            Picker("Iterations", selection: $iterations) {
                Text("20").tag(20)
                Text("50").tag(50)
                Text("100").tag(100)
            }
            .pickerStyle(.segmented)

            Button {
                Task { await runBenchmark() }
            } label: {
                Label(isBenchmarking ? "Running…" : "Run Benchmark", systemImage: "stopwatch")
            }
            .disabled(isBenchmarking || engine.detector == nil)

            if isBenchmarking {
                ProgressView(value: Double(benchmarkRuns), total: Double(iterations)) {
                    Text("\(benchmarkRuns) of \(iterations) runs")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondaryText)
                }
            }

            if let benchmarkError {
                Label(benchmarkError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }

            if let benchmark {
                let passes = benchmark.impliedFPS >= fpsTarget
                LabeledContent("Mean ± SD", value: "\(benchmark.mean.fixed(1)) ± \(benchmark.standardDeviation.fixed(1)) ms")
                LabeledContent("Min / p95 / Max", value: "\(benchmark.minimum.fixed(1)) / \(benchmark.p95.fixed(1)) / \(benchmark.maximum.fixed(1)) ms")
                LabeledContent("Model throughput") {
                    Label("\(benchmark.impliedFPS.fixed(1)) FPS", systemImage: passes ? Severity.clear.symbol : Severity.severe.symbol)
                        .foregroundStyle((passes ? Severity.clear.color : Severity.severe.color).legible)
                }
                Chart {
                    RuleMark(y: .value("Mean", benchmark.mean))
                        .foregroundStyle(.secondaryText)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("Mean").font(.caption2).foregroundStyle(.secondaryText)
                        }
                    ForEach(Array(benchmark.latenciesMs.enumerated()), id: \.offset) { index, latency in
                        BarMark(x: .value("Run", index + 1), y: .value("ms", latency))
                            .foregroundStyle(.tint)
                    }
                }
                .chartXAxisLabel("Run")
                .chartYAxisLabel("ms")
                .frame(height: 160)
            }
        } header: {
            Text("Latency Benchmark")
        }
    }

    private func runBenchmark() async {
        isBenchmarking = true
        benchmarkRuns = 0
        benchmarkError = nil
        defer { isBenchmarking = false }
        do {
            benchmark = try await engine.runBenchmark(iterations: iterations) { benchmarkRuns = $0 }
        } catch {
            benchmarkError = error.localizedDescription
        }
    }

    // MARK: - Training metrics

    private var trainingMetricsSection: some View {
        Section {
            metricField("Precision", value: $reportedPrecision)
            metricField("Recall", value: $reportedRecall)
            metricField("mAP@0.5", value: $reportedMAP50)
            metricField("mAP@0.5:0.95", value: $reportedMAP5095)
            if reportedPrecision > 0, reportedRecall > 0 {
                LabeledContent("F1-score", value: (2 * reportedPrecision * reportedRecall / (reportedPrecision + reportedRecall)).fixed(3))
            }
        } header: {
            Text("Reported Validation Metrics")
        }
    }

    private func metricField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField("0.000", value: value, format: .number.precision(.fractionLength(3)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
        }
    }
}
