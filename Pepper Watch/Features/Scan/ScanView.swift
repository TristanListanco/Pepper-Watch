//
//  ScanView.swift
//  Pepper Watch
//

import PhotosUI
import SwiftUI

struct ScanView: View {
    let isSelected: Bool

    @Environment(ScanModel.self) private var scanner
    @Environment(DetectionEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @AppStorage(SettingsKey.showLabels) private var showLabels = true
    @AppStorage(SettingsKey.showConfidence) private var showConfidence = true
    @AppStorage(SettingsKey.showPerformanceHUD) private var showPerformanceHUD = true
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.fieldName) private var fieldName = "Field A"
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0

    @State private var photoItem: PhotosPickerItem?
    @State private var photoAnalysis: PhotoAnalysis?
    @State private var isAnalyzingPhoto = false
    @State private var showGuidance = false
    @State private var isRenamingField = false
    @State private var fieldNameDraft = ""
    @State private var flashOpacity = 0.0
    @Namespace private var glassNamespace

    private var isActive: Bool { isSelected && scenePhase == .active }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            Color.white.opacity(flashOpacity).ignoresSafeArea().allowsHitTesting(false)
        }
        .task(id: isActive) {
            if isActive {
                await scanner.start()
            } else {
                scanner.stop()
            }
        }
        .onDisappear { scanner.stop() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await analyzePhoto(item) }
        }
        .onChange(of: scanner.snapshotCount) {
            flashOpacity = 0.7
            withAnimation(.easeOut(duration: 0.35)) { flashOpacity = 0 }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: scanner.snapshotCount) { _, _ in hapticsEnabled }
        .sensoryFeedback(trigger: scanner.stableSeverity) { old, new in
            guard hapticsEnabled, let new, new > (old ?? .clear), new >= .moderate else { return nil }
            return .warning
        }
        .sheet(item: $photoAnalysis) { analysis in
            PhotoAnalysisView(analysis: analysis)
        }
        .sheet(isPresented: $showGuidance) {
            NavigationStack {
                ScrollView {
                    RecommendationCard(severity: scanner.stableSeverity ?? .clear)
                        .padding()
                }
                .navigationTitle("Field Guidance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", systemImage: "checkmark") { showGuidance = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Field Name", isPresented: $isRenamingField) {
            TextField("Field A", text: $fieldNameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = fieldNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { fieldName = trimmed }
            }
        } message: {
            Text("New detections will be tagged with this field or plot name.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch scanner.status {
        case .denied:
            ContentUnavailableView {
                Label("Camera Access Needed", systemImage: "camera.fill")
            } description: {
                Text("Allow camera access in Settings to scan pepper leaves. You can still analyze photos.")
            } actions: {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.glassProminent)
                photoPickerButton(label: "Analyze a Photo")
            }
            .foregroundStyle(.white)
        case .unavailable(let message):
            ContentUnavailableView {
                Label("Camera Unavailable", systemImage: "video.slash")
            } description: {
                Text(message + "\nYou can still run the detector on photos from your library.")
            } actions: {
                photoPickerButton(label: "Analyze a Photo")
            }
            .foregroundStyle(.white)
        case .idle, .requestingPermission, .starting, .running:
            cameraLayer
        }
    }

    // MARK: - Live camera

    private var cameraLayer: some View {
        ZStack {
            CameraPreview(
                session: scanner.camera.session,
                device: scanner.captureDevice,
                onCaptureRotationChange: scanner.captureRotationChanged
            )
            DetectionOverlay(
                detections: scanner.detections,
                imageSize: scanner.imageSize,
                contentMode: .fill,
                showLabels: showLabels,
                showConfidence: showConfidence
            )
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) { topBar.padding(.horizontal) }
        .overlay(alignment: .bottom) { bottomPanel.padding(.horizontal).padding(.bottom, 8) }
        .overlay {
            if scanner.status == .starting || engine.state == .loading {
                ProgressView(engine.state == .loading ? "Loading model…" : "Starting camera…")
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            }
        }
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .top) {
                Button {
                    fieldNameDraft = fieldName
                    isRenamingField = true
                } label: {
                    Label(fieldName, systemImage: "mappin.and.ellipse")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .buttonStyle(.glass)
                .accessibilityHint("Rename the field for new detections")

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    if showPerformanceHUD, scanner.status == .running {
                        performanceChip
                    }
                    if scanner.isPaused {
                        Label("Paused", systemImage: "pause.fill")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .glassEffect(.regular.tint(.yellow.opacity(0.4)), in: .capsule)
                            .glassEffectID("paused", in: glassNamespace)
                    }
                }
            }
        }
    }

    private var performanceChip: some View {
        let belowTarget = scanner.fps > 0 && scanner.fps < fpsTarget
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: belowTarget ? "tortoise.fill" : "hare.fill")
                Text("\(scanner.fps.fixed(1)) FPS")
                    .contentTransition(.numericText(value: scanner.fps))
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            Text("\(scanner.inferenceMs.fixed(0)) ms · \(scanner.eventsLoggedThisSession) logged")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .glassEffectID("performance", in: glassNamespace)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scanner.fps.fixed(0)) frames per second, \(scanner.inferenceMs.fixed(0)) milliseconds per inference")
    }

    private var bottomPanel: some View {
        GlassEffectContainer(spacing: 16) {
            VStack(spacing: 14) {
                guidancePanel
                controls
            }
        }
    }

    private var guidancePanel: some View {
        Button {
            showGuidance = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SeverityBadge(severity: scanner.stableSeverity, compact: true)
                    Text(scanner.stableSeverity?.headline ?? "Point the camera at bell pepper leaves")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    ClassCountLabel(leafClass: .aphidInfested, count: scanner.summary.aphidCount)
                    ClassCountLabel(leafClass: .healthy, count: scanner.summary.healthyCount)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(scanner.summary.infestationRate.percentText)
                            .font(.title3.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText(value: scanner.summary.infestationRate))
                        Text("infested")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
        .animation(.smooth, value: scanner.summary)
        .accessibilityHint("Shows treatment guidance")
    }

    private var controls: some View {
        HStack(spacing: 14) {
            photoPickerButton(label: nil)

            CircleGlassButton(
                title: scanner.isPaused ? "Resume Inference" : "Pause Inference",
                systemImage: scanner.isPaused ? "play.fill" : "pause.fill"
            ) {
                scanner.togglePause()
            }

            CircleGlassButton(title: "Capture Snapshot", systemImage: "camera.shutter.button.fill", diameter: 56, isProminent: true) {
                scanner.captureSnapshot()
            }
            .disabled(scanner.status != .running)

            CircleGlassButton(
                title: scanner.isTorchOn ? "Turn Off Light" : "Turn On Light",
                systemImage: scanner.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill"
            ) {
                scanner.toggleTorch()
            }
            .disabled(!scanner.capabilities.hasTorch)

            Button {
                let presets = scanner.capabilities.zoomPresets
                let index = presets.firstIndex(of: scanner.zoom) ?? 0
                scanner.setZoom(presets[(index + 1) % presets.count])
            } label: {
                Text(scanner.zoom == 0.5 ? ".5×" : "\(Int(scanner.zoom))×")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(scanner.capabilities.zoomPresets.count < 2)
            .accessibilityLabel("Zoom \(scanner.zoom.fixed(1)) times")
        }
    }

    private func photoPickerButton(label: String?) -> some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            if let label {
                Label(label, systemImage: "photo.on.rectangle")
            } else {
                Group {
                    if isAnalyzingPhoto {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.on.rectangle")
                    }
                }
                .font(.title3)
                .frame(width: 36, height: 36)
                .accessibilityLabel("Analyze a photo")
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(label == nil ? .circle : .capsule)
        .disabled(isAnalyzingPhoto || engine.detector == nil)
    }

    // MARK: - Photo import

    private func analyzePhoto(_ item: PhotosPickerItem) async {
        isAnalyzingPhoto = true
        defer {
            isAnalyzingPhoto = false
            photoItem = nil
        }
        guard let detector = engine.detector,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = await ImageEncoder.uprightImage(from: data)
        else { return }

        let clock = ContinuousClock()
        let start = clock.now
        let detections = (try? await detector.detect(in: image)) ?? []
        photoAnalysis = PhotoAnalysis(
            image: image,
            detections: detections,
            inferenceMs: start.duration(to: clock.now) / .milliseconds(1)
        )
    }
}

private struct CircleGlassButton: View {
    let title: String
    let systemImage: String
    var diameter: CGFloat = 36
    var isProminent = false
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Image(systemName: systemImage)
                .font(isProminent ? .title : .title3)
                .frame(width: diameter, height: diameter)
        }
        .buttonBorderShape(.circle)
        .accessibilityLabel(title)

        if isProminent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

#Preview {
    ScanView(isSelected: false)
        .environment(PreviewSupport.scanner)
        .environment(PreviewSupport.engine)
}
