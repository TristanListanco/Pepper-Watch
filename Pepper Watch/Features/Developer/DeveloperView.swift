//
//  DeveloperView.swift
//  Pepper Watch
//

import SwiftData
import SwiftUI

struct DeveloperView: View {
    @Environment(DetectionEngine.self) private var engine

    @AppStorage(SettingsKey.confidenceThreshold) private var confidenceThreshold = 0.25
    @AppStorage(SettingsKey.iouThreshold) private var iouThreshold = 0.7
    @AppStorage(SettingsKey.computeUnits) private var computeUnits = ComputeUnitsOption.all.rawValue
    @AppStorage(SettingsKey.classAgnosticNMS) private var classAgnosticNMS = true
    @AppStorage(SettingsKey.captureQuality) private var captureQuality = CaptureQuality.hd720.rawValue
    @AppStorage(SettingsKey.showLabels) private var showLabels = true
    @AppStorage(SettingsKey.showConfidence) private var showConfidence = true
    @AppStorage(SettingsKey.showPerformanceHUD) private var showPerformanceHUD = true
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.autoLogEnabled) private var autoLogEnabled = true
    @AppStorage(SettingsKey.autoLogInterval) private var autoLogInterval = 3.0
    @AppStorage(SettingsKey.autoLogRequiresAphids) private var autoLogRequiresAphids = false
    @AppStorage(SettingsKey.geotagEnabled) private var geotagEnabled = true
    @AppStorage(SettingsKey.healthLogInterval) private var healthLogInterval = 30.0
    @AppStorage(SettingsKey.fieldName) private var fieldName = "Field A"
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0

    private var detectorConfiguration: DetectorConfiguration {
        DetectorConfiguration(
            confidenceThreshold: confidenceThreshold,
            iouThreshold: iouThreshold,
            computeUnits: ComputeUnitsOption(rawValue: computeUnits) ?? .all,
            classAgnosticNMS: classAgnosticNMS
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                modelSection
                detectionSection
                overlaySection
                loggingSection
                diagnosticsSection
                DataManagementSection()
                aboutSection
            }
            .navigationTitle("Developer")
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
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Model")
        } footer: {
            Text("Model card, compute devices and an on-device latency benchmark.")
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
            thresholdSlider("Confidence threshold", value: $confidenceThreshold, range: 0.05...0.95)
            thresholdSlider("IoU threshold (NMS)", value: $iouThreshold, range: 0.1...0.95)
            Toggle("One class per leaf", isOn: $classAgnosticNMS)
            Picker("Compute units", selection: $computeUnits) {
                ForEach(ComputeUnitsOption.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker("Camera resolution", selection: $captureQuality) {
                ForEach(CaptureQuality.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Button("Restore Model Defaults", systemImage: "arrow.counterclockwise") {
                confidenceThreshold = engine.modelInfo?.defaultConfidence ?? 0.25
                iouThreshold = engine.modelInfo?.defaultIoU ?? 0.7
                computeUnits = ComputeUnitsOption.all.rawValue
                classAgnosticNMS = true
            }
        } header: {
            Text("Detection")
        } footer: {
            Text("Thresholds apply live. Lower confidence finds more early-stage damage but adds false alarms. “One class per leaf” drops the weaker label when the model marks the same leaf as both healthy and infested. Changing compute units reloads the model; camera resolution applies next time scanning starts.")
        }
    }

    private func thresholdSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(title) {
                Text(value.wrappedValue.fixed(2)).monospacedDigit()
            }
            Slider(value: value, in: range, step: 0.05)
                .accessibilityLabel(title)
                .accessibilityValue(value.wrappedValue.fixed(2))
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
            LabeledContent("Field name") {
                TextField("Field A", text: $fieldName)
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Auto-log detections", isOn: $autoLogEnabled)
            if autoLogEnabled {
                Stepper(value: $autoLogInterval, in: 1...30, step: 1) {
                    LabeledContent("Log every", value: "\(Int(autoLogInterval)) s")
                }
                Toggle("Only when aphids are found", isOn: $autoLogRequiresAphids)
            }
            Toggle("Geotag detections", isOn: $geotagEnabled)
            Picker("Health log interval", selection: $healthLogInterval) {
                Text("15 s").tag(15.0)
                Text("30 s").tag(30.0)
                Text("1 min").tag(60.0)
                Text("5 min").tag(300.0)
            }
        } header: {
            Text("Logging")
        } footer: {
            Text("Everything stays on this device. Auto-logging saves a frame, its bounding boxes and timestamp at the chosen interval while leaves are in view.")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            NavigationLink {
                PerformanceMonitorView()
            } label: {
                Label("Performance Monitor", systemImage: "gauge.with.dots.needle.67percent")
            }
            NavigationLink {
                SystemLogView()
            } label: {
                Label("System Log", systemImage: "list.bullet.rectangle")
            }
            Stepper(value: $fpsTarget, in: 5...60, step: 1) {
                LabeledContent("Real-time target", value: "\(Int(fpsTarget)) FPS")
            }
        } header: {
            Text("Diagnostics")
        } footer: {
            Text("The thesis requires at least 17 FPS for real-time processing.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pepper Watch")
                    .font(.headline)
                Text("On-device companion to “Development of YOLOv8n Aphid Damage Detection and Offline Monitoring for Bell Pepper (Capsicum annuum) on Raspberry Pi 5”, MSU–Iligan Institute of Technology.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            LabeledContent("Version", value: Bundle.main.appVersion)
            LabeledContent("Classes", value: LeafClass.allCases.map(\.rawValue).joined(separator: ", "))
            LabeledContent("Network use", value: "None, fully offline")
        }
    }
}

// MARK: - Data management

private struct DataManagementSection: View {
    @Query private var events: [DetectionEvent]
    @Query private var sessions: [ScanSession]
    @Query private var logs: [SystemLog]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.systemLogger) private var logger
    @State private var isConfirmingErase = false
    @State private var storageBytes: Int64?

    var body: some View {
        Section {
            LabeledContent("Detection events", value: events.count.formatted())
            LabeledContent("Bounding boxes", value: events.reduce(0) { $0 + $1.aphidCount + $1.healthyCount }.formatted())
            LabeledContent("Scan sessions", value: sessions.count.formatted())
            LabeledContent("System log entries", value: logs.count.formatted())
            LabeledContent("Storage used", value: storageBytes.map { $0.formatted(.byteCount(style: .file)) } ?? "…")

            ShareLink(item: CSVExporter.detections(events), preview: SharePreview("Detections CSV")) {
                Label("Export Detections (CSV)", systemImage: "tablecells")
            }
            .disabled(events.isEmpty)
            ShareLink(item: CSVExporter.sessions(sessions), preview: SharePreview("Sessions CSV")) {
                Label("Export Sessions (CSV)", systemImage: "timer")
            }
            .disabled(sessions.isEmpty)
            ShareLink(item: CSVExporter.systemLogs(logs), preview: SharePreview("System log CSV")) {
                Label("Export System Log (CSV)", systemImage: "doc.text")
            }
            .disabled(logs.isEmpty)

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
            .disabled(events.isEmpty && sessions.isEmpty && logs.isEmpty)
        } header: {
            Text("Local Data")
        } footer: {
            Text("Stored with SwiftData on this device only.")
        }
        .task { refreshStorage() }
        .confirmationDialog("Erase all local data?", isPresented: $isConfirmingErase, titleVisibility: .visible) {
            Button("Erase Everything", role: .destructive) {
                eraseAll()
            }
        } message: {
            Text("Deletes every scan, image, session and log entry. This can't be undone.")
        }
    }

    private func eraseAll() {
        for event in events { modelContext.delete(event) }
        for session in sessions { modelContext.delete(session) }
        for log in logs { modelContext.delete(log) }
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
        .modelContainer(PreviewSupport.container)
}
