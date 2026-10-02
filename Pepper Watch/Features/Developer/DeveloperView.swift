//
//  DeveloperView.swift
//  Pepper Watch
//

import AppIntents
import SwiftData
import SwiftUI

struct DeveloperView: View {
    @Environment(DetectionEngine.self) private var engine

    @AppStorage(SettingsKey.confidenceThreshold) private var confidenceThreshold = 0.25
    @AppStorage(SettingsKey.iouThreshold) private var iouThreshold = 0.7
    @AppStorage(SettingsKey.computeUnits) private var computeUnits = ComputeUnitsOption.all.rawValue
    @AppStorage(SettingsKey.classAgnosticNMS) private var classAgnosticNMS = true
    @AppStorage(SettingsKey.fastPrediction) private var fastPrediction = true
    @AppStorage(SettingsKey.pipelinedInference) private var pipelinedInference = true
    @AppStorage(SettingsKey.lensSmudgeCheck) private var lensSmudgeCheck = true
    @AppStorage(SettingsKey.captureQuality) private var captureQuality = CaptureQuality.hd720.rawValue
    @AppStorage(SettingsKey.showLabels) private var showLabels = true
    @AppStorage(SettingsKey.showConfidence) private var showConfidence = true
    @AppStorage(SettingsKey.showPerformanceHUD) private var showPerformanceHUD = true
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.autoLogEnabled) private var autoLogEnabled = true
    @AppStorage(SettingsKey.autoLogInterval) private var autoLogInterval = 10.0
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0
    @AppStorage(SettingsKey.autoLogRequiresAphids) private var autoLogRequiresAphids = false
    @AppStorage(SettingsKey.geotagEnabled) private var geotagEnabled = true
    @AppStorage(SettingsKey.strictGeofence) private var strictGeofence = false
    @State private var showsWidgetGallery = Self.opensPage("widgets")
    @State private var showsModelCard = Self.opensPage("model")
    @State private var showsPerformance = Self.opensPage("performance")
    @State private var showsSessions = Self.opensPage("sessions")

    /// Debug builds accept `-PWDeveloperPage widgets|model|performance|sessions` to open that page for screenshots.
    private static func opensPage(_ page: String) -> Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "PWDeveloperPage") == page
        #else
        false
        #endif
    }

    private var detectorConfiguration: DetectorConfiguration {
        DetectorConfiguration(
            confidenceThreshold: confidenceThreshold,
            iouThreshold: iouThreshold,
            computeUnits: ComputeUnitsOption(rawValue: computeUnits) ?? .all,
            classAgnosticNMS: classAgnosticNMS,
            fastPrediction: fastPrediction
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                PerformanceSection { showsPerformance = true }
                modelSection
                detectionSection
                cameraSection
                overlaySection
                loggingSection
                toolsSection
                siriSection
                DataManagementSection()
                aboutSection
            }
            // The same subtle wash as the Fields tab, behind the glass performance card.
            .scrollContentBackground(.hidden)
            .summaryGradientBackground()
            .navigationTitle("Developer")
            .navigationDestination(isPresented: $showsWidgetGallery) { WidgetGalleryView() }
            .navigationDestination(isPresented: $showsModelCard) { ModelInfoView() }
            .navigationDestination(isPresented: $showsPerformance) { PerformanceMonitorView() }
            .navigationDestination(isPresented: $showsSessions) { SessionsTableView() }
            .task(id: detectorConfiguration) {
                // Debounce slider drags: a newer value cancels this task before it applies.
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await engine.configure(detectorConfiguration)
            }
        }
    }

    // MARK: - Sections

    private var modelSection: some View {
        Section {
            NavigationLink {
                ModelInfoView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AphidDetector.modelName).font(.headline)
                        Text(engineStatus)
                            .font(.caption)
                            .foregroundStyle(.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            }
            Picker("Compute units", selection: $computeUnits) {
                ForEach(ComputeUnitsOption.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Fast prediction", isOn: $fastPrediction)
            Toggle("Pipelined inference", isOn: $pipelinedInference)
            Stepper(value: $fpsTarget, in: 5...60, step: 1) {
                LabeledContent("Real-time target", value: "\(Int(fpsTarget)) FPS")
            }
        } header: {
            Text("Model")
        }
    }

    private var engineStatus: String {
        switch engine.state {
        case .idle: "Not loaded"
        case .loading: "Loading…"
        case .ready:
            "Ready on \(engine.activeComputeUnits?.shortTitle ?? "—") · loaded in \(engine.loadDuration.map { ($0 / .milliseconds(1)).fixed(0) } ?? "—") ms"
        case .failed(let message): "Failed: \(message)"
        }
    }

    private var detectionSection: some View {
        Section {
            thresholdSlider("Confidence threshold", value: $confidenceThreshold, range: 0.05...0.95, modelDefault: engine.modelInfo?.defaultConfidence ?? 0.25)
            thresholdSlider("IoU threshold (NMS)", value: $iouThreshold, range: 0.1...0.95, modelDefault: engine.modelInfo?.defaultIoU ?? 0.7)
            Toggle("One class per leaf", isOn: $classAgnosticNMS)
            Button("Restore Model Defaults", systemImage: "arrow.counterclockwise") {
                confidenceThreshold = engine.modelInfo?.defaultConfidence ?? 0.25
                iouThreshold = engine.modelInfo?.defaultIoU ?? 0.7
                computeUnits = ComputeUnitsOption.all.rawValue
                classAgnosticNMS = true
                fastPrediction = true
                pipelinedInference = true
                lensSmudgeCheck = true
            }
        } header: {
            Text("Detection")
        }
    }

    /// The fill grows from the model's default (iOS 26 neutral value), so it's clear how far a
    /// threshold is from what the model was exported with; each 0.05 step gets a tick.
    private func thresholdSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, modelDefault: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Text(value.wrappedValue.fixed(2)).monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.05, neutralValue: modelDefault) {
                Text(title)
            }
            .accessibilityValue(value.wrappedValue.fixed(2))
        }
    }

    private var cameraSection: some View {
        Section {
            Picker("Resolution", selection: $captureQuality) {
                ForEach(CaptureQuality.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Lens smudge check", isOn: $lensSmudgeCheck)
        } header: {
            Text("Camera")
        }
    }

    private var overlaySection: some View {
        Section("Live Overlay") {
            Toggle("Class labels", isOn: $showLabels)
            Toggle("Confidence scores", isOn: $showConfidence)
                .disabled(!showLabels)
            Toggle("Performance HUD", isOn: $showPerformanceHUD)
            Toggle("Haptic alerts", isOn: $hapticsEnabled)
        }
    }

    private var loggingSection: some View {
        Section {
            Toggle("Auto-log detections", isOn: $autoLogEnabled)
            if autoLogEnabled {
                Stepper(value: $autoLogInterval, in: 1...30, step: 1) {
                    LabeledContent("Log every", value: "\(Int(autoLogInterval)) s")
                }
                Toggle("Only when aphids are found", isOn: $autoLogRequiresAphids)
            }
            Toggle("Geotag detections", isOn: $geotagEnabled)
            Toggle("Strict geofence", isOn: $strictGeofence)
        } header: {
            Text("Logging")
        }
    }

    private var toolsSection: some View {
        Section {
            NavigationLink {
                SystemLogView()
            } label: {
                Label("System Log", systemImage: "list.bullet.rectangle")
            }
            Button("Show Tips Again", systemImage: "lightbulb") {
                PepperWatchTips.resetOnNextLaunch()
            }
        } header: {
            Text("Tools")
        }
    }

    private var siriSection: some View {
        Section {
            SiriTipView(intent: CheckFieldStatusIntent())
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } header: {
            Text("Siri & Shortcuts")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pepper Watch")
                    .font(.headline)
                Text("On-device companion to “Development of YOLOv8n Aphid Damage Detection and Offline Monitoring for Bell Pepper (Capsicum annuum) on Raspberry Pi 5”, MSU–Iligan Institute of Technology.")
                    .font(.caption)
                    .foregroundStyle(.secondaryText)
            }
            .padding(.vertical, 4)
            LabeledContent("Version", value: Bundle.main.appVersion)
            LabeledContent("Network use", value: "None, fully offline")
        }
    }
}

// MARK: - Performance

/// Live readings at the top of the tab, in a Liquid Glass card that opens the Performance Monitor.
private struct PerformanceSection: View {
    let openMonitor: () -> Void

    @Environment(ScanModel.self) private var scanner
    @Environment(DeviceMonitor.self) private var monitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query(ThroughputReading.lastSession) private var lastSessions: [ScanSession]
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0

    var body: some View {
        Section {
            Button(action: openMonitor) {
                HStack(spacing: 12) {
                    summary
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))
            .accessibilityHint("Opens the Performance Monitor")
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .task { await monitor.monitor() }
        }
    }

    private var summary: some View {
        let reading = ThroughputReading.current(scanner: scanner, lastSession: lastSessions.first)
        return VStack(alignment: .leading, spacing: 12) {
            verdict(reading)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                // One row when there's room (iPad), two on iPhone.
                if horizontalSizeClass == .regular {
                    GridRow { speedMetrics(reading); deviceMetrics }
                } else {
                    GridRow { speedMetrics(reading) }
                    GridRow { deviceMetrics }
                }
            }
        }
        // Forms space label icons into a column; keep captions tight like a dashboard.
        .labelIconToTitleSpacing(6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func speedMetrics(_ reading: ThroughputReading?) -> some View {
        metric("Throughput", value: reading.map { "\($0.fps.fixed(1)) FPS" } ?? "—", symbol: "speedometer")
        metric("Inference", value: reading.map { "\($0.inferenceMs.fixed(1)) ms" } ?? "—", symbol: "timer")
    }

    @ViewBuilder
    private var deviceMetrics: some View {
        metric("Thermal state", value: monitor.snapshot.thermalState.title, symbol: monitor.snapshot.thermalState.symbol)
        metric("Memory", value: "\(monitor.snapshot.memoryMB.fixed(0)) MB", symbol: "memorychip")
    }

    @ViewBuilder
    private func verdict(_ reading: ThroughputReading?) -> some View {
        if let reading {
            let passes = reading.fps >= fpsTarget
            let subject = reading.isLive ? "Scanning now" : "Last scan"
            let status = reading.isLive
                ? (passes ? "meets" : "is below")
                : (passes ? "met" : "was below")
            Label("\(subject) \(status) the \(fpsTarget.fixed(0)) FPS target", systemImage: passes ? Severity.clear.symbol : Severity.severe.symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle((passes ? Severity.clear.color : Severity.severe.color).legible)
        } else {
            Label("Scan once to measure throughput", systemImage: "gauge.with.dots.needle.67percent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondaryText)
        }
    }

    private func metric(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(.secondaryText)
                .lineLimit(1)
            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Data management

private struct DataManagementSection: View {
    @Query private var events: [DetectionEvent]
    @Query private var sessions: [ScanSession]
    @Query private var logs: [SystemLog]
    @Query private var fields: [Field]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.systemLogger) private var logger
    @State private var isConfirmingErase = false
    @State private var storageBytes: Int64?
    /// The sessions export is being prepared; its row shows a spinner until the share sheet opens.
    @State private var isExporting = false
    @State private var exportError: String?
    /// Where the export row is on screen, for the share sheet's popover on iPad.
    @State private var exportFrame: CGRect?

    var body: some View {
        Section {
            LabeledContent("Fields", value: fields.count.formatted())
            LabeledContent("Detection events", value: events.count.formatted())
            LabeledContent("Bounding boxes", value: events.reduce(0) { $0 + $1.aphidCount + $1.healthyCount }.formatted())
            LabeledContent("Scan sessions", value: sessions.count.formatted())
            LabeledContent("System log entries", value: logs.count.formatted())
            LabeledContent("Storage used", value: storageBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "…")

            // Detections export from Insights, and the log from the System Log page.
            exportSessionsButton

            Button("Generate Demo Data", systemImage: "wand.and.stars") {
                DemoDataGenerator.generate(in: modelContext)
                refreshStorage()
            }
            Button("Remove Demo Data", systemImage: "wand.and.rays.inverse") {
                DemoDataGenerator.removeDemoData(in: modelContext)
                logger?.log(category: "data", "Removed demo data")
                refreshStorage()
            }
            .disabled(!events.contains { $0.source == .demo })

            Button("Erase All Data", systemImage: "trash", role: .destructive) {
                isConfirmingErase = true
            }
            .disabled(events.isEmpty && sessions.isEmpty && logs.isEmpty && fields.isEmpty)
        } header: {
            Text("Local Data")
        }
        .task { refreshStorage() }
        .confirmationDialog("Erase all local data?", isPresented: $isConfirmingErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive) {
                eraseAll()
            }
        } message: {
            Text("Deletes every field, scan, image, session and log entry. This can't be undone.")
        }
        .alert("Couldn't Export", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private var exportSessionsButton: some View {
        Button {
            exportSessions()
        } label: {
            HStack {
                Label("Export Sessions (CSV)", systemImage: "timer")
                Spacer()
                if isExporting {
                    ProgressView()
                }
            }
            .contentShape(.rect)
        }
        .disabled(sessions.isEmpty || isExporting)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { exportFrame = $0 }
        .accessibilityValue(isExporting ? "Preparing" : "")
    }

    /// Builds the CSV, writes it to a file and opens the share sheet, with a spinner meanwhile.
    private func exportSessions() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            // Let the spinner appear before the rows are read.
            try? await Task.sleep(for: .milliseconds(120))
            do {
                let url = try await CSVExporter.sessions(sessions).writeToTemporaryFile()
                isExporting = false
                SharePresenter.present(file: url, title: "Sessions · \(sessions.count) sessions", symbol: "timer", from: exportFrame)
            } catch {
                isExporting = false
                exportError = error.localizedDescription
                logger?.log(.error, category: "data", "Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func eraseAll() {
        for event in events { modelContext.delete(event) }
        for session in sessions { modelContext.delete(session) }
        for log in logs { modelContext.delete(log) }
        for field in fields { modelContext.delete(field) }
        try? modelContext.save()
        logger?.log(.warning, category: "data", "All local data erased")
        refreshStorage()
    }

    private func refreshStorage() {
        guard let directory = modelContext.container.configurations.first?.url.deletingLastPathComponent() else { return }
        Task {
            storageBytes = await DiskUsage.sizeInBackground(of: directory)
        }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    DeveloperView()
        .environment(PreviewSupport.engine)
        .environment(PreviewSupport.scanner)
        .environment(DeviceMonitor())
        .modelContainer(PreviewSupport.container)
}
