//
//  ScanView.swift
//  Pepper Watch
//

import PhotosUI
import SwiftData
import SwiftUI
import TipKit

struct ScanView: View {
    let field: Field

    @Environment(ScanModel.self) private var scanner
    @Environment(DetectionEngine.self) private var engine
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage(SettingsKey.showLabels) private var showLabels = true
    @AppStorage(SettingsKey.showConfidence) private var showConfidence = true
    @AppStorage(SettingsKey.showPerformanceHUD) private var showPerformanceHUD = true
    @AppStorage(SettingsKey.hapticsEnabled) private var hapticsEnabled = true
    @AppStorage(SettingsKey.strictGeofence) private var strictGeofence = false
    @AppStorage(SettingsKey.fpsTarget) private var fpsTarget = 17.0

    @State private var photoItem: PhotosPickerItem?
    @State private var photoAnalysis: PhotoAnalysis?
    @State private var isAnalyzingPhoto = false
    @State private var isVisible = false
    /// Round controls grow with Dynamic Type (capped over the camera) instead of staying 44 pt.
    @ScaledMetric(relativeTo: .title3) private var controlSize = 44.0
    @ScaledMetric(relativeTo: .caption) private var zoomSize = 36.0
    @State private var isDropTargeted = false
    @Namespace private var glassNamespace

    private var isActive: Bool { isVisible && scenePhase == .active }

    /// iPad keeps its controls in a rail on the side, like the Camera app.
    private var usesSideRail: Bool { horizontalSizeClass == .regular }

    /// Saves a new name as soon as renaming ends; blank names are ignored.
    private var nameBinding: Binding<String> {
        Binding {
            field.name
        } set: { newName in
            guard field.rename(to: newName) else { return }
            try? modelContext.save()
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            content
            // A quick white flash for each snapshot, like the Camera app.
            Color.white
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .keyframeAnimator(initialValue: 0.0, trigger: scanner.snapshotCount) { flash, opacity in
                    flash.opacity(opacity)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(0.7, duration: 0.03)
                        CubicKeyframe(0, duration: 0.35)
                    }
                }
        }
        // Tap the title to rename the field in place.
        .navigationTitle(nameBinding)
        .toolbarTitleMenu { RenameButton() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if scanner.capabilities.hasTorch {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(scanner.isTorchOn ? "Turn Off Light" : "Turn On Light", systemImage: scanner.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill") {
                        scanner.toggleTorch()
                    }
                    .contentTransition(.symbolEffect(.replace))
                }
            }
        }
        // White glass controls stay legible over any leaves; the accent green blended into them.
        .tint(.white)
        .onAppear { isVisible = true }
        .onDisappear {
            isVisible = false
            scanner.stop()
        }
        .task(id: isActive) {
            if isActive {
                await scanner.start(field: field)
            } else {
                scanner.stop()
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { await analyzePhoto(item) }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: scanner.snapshotCount) { _, _ in hapticsEnabled }
        .sensoryFeedback(.selection, trigger: scanner.zoom) { _, _ in hapticsEnabled }
        .sensoryFeedback(.impact(weight: .light), trigger: scanner.isPaused) { _, _ in hapticsEnabled }
        .sensoryFeedback(trigger: scanner.stableSeverity) { old, new in
            guard hapticsEnabled, let new, new > (old ?? .clear), new >= .moderate else { return nil }
            return .warning
        }
        .sheet(item: $photoAnalysis) { analysis in
            PhotoAnalysisView(analysis: analysis, field: field)
                .tint(Color(.accent))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // Drop a photo from Photos or Files onto the scanner to analyze it, handy in iPad split view.
        .dropDestination(for: DroppedPhoto.self) { photos, _ in
            guard let photo = photos.first, engine.detector != nil, !isAnalyzingPhoto else { return false }
            Task { await analyzePhoto(data: photo.data) }
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                Label("Drop to Analyze", systemImage: "photo.on.rectangle.angled")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .glassEffect(.regular, in: .capsule)
                    .environment(\.colorScheme, .dark)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth, value: isDropTargeted)
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
        .overlay(alignment: usesSideRail ? .bottomLeading : .bottom) {
            if usesSideRail {
                statusStack
                    .frame(maxWidth: 420, alignment: .leading)
                    .padding(24)
            } else {
                VStack(spacing: 18) {
                    statusStack
                    bottomControls
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .overlay(alignment: .trailing) {
            if usesSideRail {
                sideRail
                    .padding(.trailing, 28)
            }
        }
        .overlay {
            if scanner.status == .starting || engine.state == .loading {
                ProgressView(engine.state == .loading ? "Loading model…" : "Starting camera…")
                    .padding()
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))
            } else if scanner.status == .running, scanner.isPaused {
                Button {
                    startDetecting()
                } label: {
                    Label("Start Detecting", systemImage: "play.fill")
                        .font(.headline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .popoverTip(StartDetectingTip())
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth, value: scanner.isPaused)
        // Controls over the camera always use dark glass with white text.
        .environment(\.colorScheme, .dark)
        // Text grows with Dynamic Type, up to a size where the controls still fit over the camera.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var topBar: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(alignment: .top) {
                GeofenceBadge(status: scanner.geofenceStatus, fieldName: field.name)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("geofence", in: glassNamespace)

                Spacer()

                if showPerformanceHUD, scanner.status == .running {
                    performanceChip
                }
            }
        }
    }

    private var performanceChip: some View {
        let belowTarget = scanner.fps > 0 && scanner.fps < fpsTarget
        return VStack(alignment: .trailing, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: belowTarget ? "tortoise.fill" : "hare.fill")
                    .contentTransition(.symbolEffect(.replace))
                Text("\(scanner.fps.fixed(1)) FPS")
                    .contentTransition(.numericText(value: scanner.fps))
            }
            .font(.caption.weight(.semibold).monospacedDigit())
            HStack(spacing: 0) {
                // How long this session has run; the system updates it without redrawing the view.
                if let start = scanner.sessionStartedAt {
                    Text(timerInterval: start...Date.distantFuture, countsDown: false)
                    Text(" · ")
                }
                Text("\(scanner.inferenceMs.fixed(0)) ms · \(scanner.eventsLoggedThisSession) logged")
                    // The count rolls up as leaves are saved.
                    .contentTransition(.numericText(value: Double(scanner.eventsLoggedThisSession)))
                    .animation(.smooth, value: scanner.eventsLoggedThisSession)
            }
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

    // MARK: - Status

    /// Banners when something needs attention, then the two leaf counters.
    private var statusStack: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(alignment: usesSideRail ? .leading : .center, spacing: 12) {
                if let status = scanner.geofenceStatus, status.presence == .outside {
                    outsideFieldBanner(status)
                }
                if scanner.isLensSmudged, !scanner.isPaused {
                    lensBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: 10) {
                    LeafCounter(leafClass: .aphidInfested, count: scanner.summary.aphidCount)
                    LeafCounter(leafClass: .healthy, count: scanner.summary.healthyCount)
                }
            }
            .frame(maxWidth: 640, alignment: usesSideRail ? .leading : .center)
            .animation(.smooth, value: scanner.isLensSmudged)
        }
    }

    /// Vision flagged the lens as smudged; a dirty lens hides early aphid damage.
    private var lensBanner: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Wipe the camera lens")
                    .font(.subheadline.weight(.semibold))
                Text("It looks smudged, which blurs leaves and hides early damage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "camera.aperture")
                .font(.title3)
                .foregroundStyle(.yellow)
                // A wiggle every few seconds draws the eye while the lens needs wiping (SF Symbols 6).
                .symbolEffect(.wiggle, options: .repeat(.periodic(delay: 3)), isActive: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func outsideFieldBanner(_ status: GeofenceStatus) -> some View {
        let isBlocked = scanner.isLoggingBlockedByGeofence
        return VStack(alignment: .leading, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Outside \(field.name)")
                        .font(.subheadline.weight(.semibold))
                    Text(isBlocked
                         ? "\(status.distanceToEdge?.distanceText ?? "Some distance") from the boundary. Detections aren't being logged."
                         : "Logging anyway. These scans are marked unverified.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "location.slash.fill")
                    .foregroundStyle(Severity.low.color)
            }
            HStack(spacing: 10) {
                Button("Directions", systemImage: "figure.walk") {
                    PlaceNamer.openDirections(to: field.region)
                }
                .buttonStyle(.glass)
                if isBlocked, !strictGeofence {
                    Button("Scan Anyway", systemImage: "exclamationmark.triangle") {
                        scanner.allowsLoggingOutsideField = true
                    }
                    .buttonStyle(.glass)
                }
            }
            // The buttons share the banner's width (iOS 26).
            .buttonSizing(.flexible)
            .font(.caption.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(Severity.low.color.opacity(0.25)), in: .rect(cornerRadius: 22))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Controls

    /// iPhone: zoom above a row of library, shutter and pause, like the Camera app.
    private var bottomControls: some View {
        VStack(spacing: 16) {
            if scanner.capabilities.zoomPresets.count > 1 {
                zoomPresets(axis: .horizontal)
            }
            HStack {
                photoPickerButton(label: nil)
                Spacer()
                shutterButton
                Spacer()
                pauseButton
            }
            .padding(.horizontal, 24)
        }
    }

    /// iPad: the same controls down the trailing edge, shutter in the middle.
    private var sideRail: some View {
        VStack(spacing: 28) {
            pauseButton
            if scanner.capabilities.zoomPresets.count > 1 {
                zoomPresets(axis: .vertical)
            }
            shutterButton
            photoPickerButton(label: nil)
        }
    }

    private var shutterButton: some View {
        ShutterButton {
            scanner.captureSnapshot()
        }
        // The space bar takes a snapshot with a hardware keyboard, like the Camera app.
        .keyboardShortcut(.space, modifiers: [])
        .help("Capture Snapshot (Space)")
        .disabled(scanner.status != .running || scanner.isPaused || scanner.isLoggingBlockedByGeofence)
        .popoverTip(SnapshotTip())
    }

    private var pauseButton: some View {
        Button {
            if scanner.isPaused { startDetecting() } else { scanner.togglePause() }
        } label: {
            Image(systemName: scanner.isPaused ? "play.fill" : "pause.fill")
                .font(.title3)
                .frame(width: controlSize, height: controlSize)
                .contentTransition(.symbolEffect(.replace))
        }
        .accessibilityLabel(scanner.isPaused ? "Start Detecting" : "Pause Detecting")
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .keyboardShortcut("p", modifiers: [])
        .help(scanner.isPaused ? "Start Detecting (P)" : "Pause Detecting (P)")
        .disabled(scanner.status != .running)
    }

    /// Tap a lens preset directly; the selected one reads "2×", the others just "2".
    private func zoomPresets(axis: Axis) -> some View {
        let layout = axis == .horizontal ? AnyLayout(HStackLayout(spacing: 2)) : AnyLayout(VStackLayout(spacing: 2))
        return layout {
            ForEach(scanner.capabilities.zoomPresets, id: \.self) { preset in
                let isSelected = preset == scanner.zoom
                let number = preset == 0.5 ? ".5" : preset.formatted(.number.precision(.fractionLength(0...1)))
                Button {
                    scanner.setZoom(preset)
                } label: {
                    Text(isSelected ? "\(number)×" : number)
                        .font(isSelected ? .caption.weight(.bold).monospacedDigit() : .caption2.weight(.bold).monospacedDigit())
                        .frame(width: zoomSize, height: zoomSize)
                        .background(isSelected ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(.clear), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .hoverEffect(.highlight)
                .help("Zoom \(number)×")
                .accessibilityLabel("Zoom \(number) times")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .foregroundStyle(.white)
        .padding(3)
        .glassEffect(.regular.interactive(), in: .capsule)
        .animation(.smooth(duration: 0.2), value: scanner.zoom)
    }

    private func startDetecting() {
        scanner.togglePause()
        StartDetectingTip().invalidate(reason: .actionPerformed)
        SnapshotTip.hasStartedDetecting = true
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
                .frame(width: controlSize, height: controlSize)
                .accessibilityLabel("Analyze a photo")
            }
        }
        .buttonStyle(.glass)
        .buttonBorderShape(label == nil ? .circle : .capsule)
        .help("Analyze a Photo")
        .disabled(isAnalyzingPhoto || engine.detector == nil)
    }

    // MARK: - Photo import

    private func analyzePhoto(_ item: PhotosPickerItem) async {
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await analyzePhoto(data: data)
    }

    /// Runs the detector on a picked or dropped photo and shows the result.
    private func analyzePhoto(data: Data) async {
        isAnalyzingPhoto = true
        defer { isAnalyzingPhoto = false }
        guard let detector = engine.detector,
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

/// A white shutter like the Camera app's: a ring around a disc that shrinks while pressed.
private struct ShutterButton: View {
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .largeTitle) private var diameter = 74.0

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: diameter, height: diameter)
                Circle()
                    .fill(.white)
                    .frame(width: diameter - 14, height: diameter - 14)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .contentShape(.circle)
        }
        .buttonStyle(ShutterPressStyle())
        .hoverEffect(.lift)
        .accessibilityLabel("Capture Snapshot")
    }

    private struct ShutterPressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.9 : 1)
                .animation(.smooth(duration: 0.15), value: configuration.isPressed)
        }
    }
}

/// One class's count on glass: white text, with the class color as a small dot for identity.
private struct LeafCounter: View {
    let leafClass: LeafClass
    let count: Int

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(leafClass.color)
                .frame(width: 9, height: 9)
            Text(count, format: .number)
                .font(.headline.monospacedDigit())
                .contentTransition(.numericText(value: Double(count)))
            Text(leafClass.shortName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: .capsule)
        .animation(.smooth, value: count)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        ScanView(field: Field(name: "North Plot", locationName: "Claveria", latitude: 8.61, longitude: 124.89, radiusMeters: 100))
    }
    .environment(PreviewSupport.scanner)
    .environment(PreviewSupport.engine)
}
