//
//  ScanModel.swift
//  Pepper Watch
//

import AVFoundation
import CoreML
import CoreLocation
import Observation
import SwiftData

struct PerformanceSample: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let fps: Double
    let latencyMs: Double
}

/// Live scanning state: camera lifecycle, smoothed metrics, auto-logging and session records.
@Observable
final class ScanModel {
    enum Status: Equatable {
        case idle
        case requestingPermission
        case denied
        case unavailable(String)
        case starting
        case running
    }

    private(set) var status: Status = .idle
    private(set) var detections: [Detection] = []
    private(set) var imageSize: CGSize = .zero
    private(set) var summary = DetectionSummary()
    /// Severity only changes after it holds for several frames, so guidance and haptics don't flicker.
    private(set) var stableSeverity: Severity?
    private(set) var fps: Double = 0
    private(set) var inferenceMs: Double = 0
    private(set) var isPaused = false
    private(set) var isTorchOn = false
    private(set) var zoom: Double = 1
    private(set) var capabilities = CameraCapabilities()
    private(set) var captureDevice: AVCaptureDevice?
    private(set) var performanceSamples: [PerformanceSample] = []
    private(set) var sessionStartedAt: Date?
    private(set) var eventsLoggedThisSession = 0
    private(set) var snapshotCount = 0
    /// Vision thinks the lens is smudged; the scanner asks the farmer to wipe it.
    private(set) var isLensSmudged = false
    /// How much of the device scanning uses, from heat, Low Power Mode and settings.
    private(set) var resourcePlan = ResourcePlan.current(allowsPipelining: false, lensCheck: false)

    /// Camera frames analyzed at once: 2 on devices with a Neural Engine while cool, else 1.
    var framesInFlight: Int { resourcePlan.framesInFlight }
    /// The field being scanned. Detections are logged to it and verified against its geofence.
    private(set) var field: Field?
    /// The user chose to keep logging while outside the field (not allowed in strict mode).
    var allowsLoggingOutsideField = false

    let camera = CameraService()

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let engine: DetectionEngine
    @ObservationIgnored private let logger: SystemLogger
    @ObservationIgnored private let location: LocationProvider
    @ObservationIgnored private let geofence: GeofenceService
    @ObservationIgnored private var backgroundTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var latestFrame: FrameResult?
    @ObservationIgnored private var lastFrameAt: ContinuousClock.Instant?
    @ObservationIgnored private var lastAutoLogAt = Date.distantPast
    /// Auto-log waits for the view to hold steady and skips views it already saved.
    @ObservationIgnored private var lastAutoLogged: [Detection] = []
    @ObservationIgnored private var steadySummary: DetectionSummary?
    @ObservationIgnored private var steadyFrames = 0
    @ObservationIgnored private var lastHealthLogAt = Date.distantPast
    @ObservationIgnored private var severityCandidate: Severity?
    @ObservationIgnored private var severityCandidateFrames = 0
    @ObservationIgnored private var smudgedChecks = 0

    // Current session accumulators.
    @ObservationIgnored private var session: ScanSession?
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var activeSeconds = 0.0
    @ObservationIgnored private var inferenceTotalMs = 0.0
    @ObservationIgnored private var peakAphidCount = 0

    init(context: ModelContext, engine: DetectionEngine, logger: SystemLogger, location: LocationProvider, geofence: GeofenceService) {
        self.context = context
        self.engine = engine
        self.logger = logger
        self.location = location
        self.geofence = geofence

        let camera = camera
        backgroundTasks = [
            Task { [weak self] in
                for await frame in camera.frames {
                    self?.handle(frame)
                }
            },
            Task { [weak self] in
                for await detector in Observations({ engine.detector }) {
                    camera.setDetector(detector)
                    // Compute units may have changed with the reload.
                    self?.updateResourcePlan()
                }
            },
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: ProcessInfo.thermalStateDidChangeNotification) {
                    self?.logThermalChange()
                    self?.updateResourcePlan()
                }
            },
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange) {
                    self?.updateResourcePlan()
                }
            },
            Task { [weak self] in
                for await confidence in camera.lensChecks {
                    self?.handleLensCheck(confidence)
                }
            },
        ]
    }

    /// Applies the current resource plan: two frames in flight keep a Neural Engine busy on newer
    /// devices, while heat and Low Power Mode lower the camera frame rate and pause the lens check.
    func updateResourcePlan(force: Bool = false) {
        let hasNeuralEngine = MLComputeDevice.allComputeDevices.contains { if case .neuralEngine = $0 { true } else { false } }
        let plan = ResourcePlan.current(
            allowsPipelining: AppSettings.pipelinedInference && hasNeuralEngine && engine.activeComputeUnits != .cpuOnly,
            lensCheck: AppSettings.lensSmudgeCheck
        )
        guard force || plan != resourcePlan else { return }
        let modeChanged = plan.mode != resourcePlan.mode
        resourcePlan = plan
        camera.setMaxInFlight(plan.framesInFlight)
        camera.setFrameRateCap(plan.cameraFrameRate)
        camera.setChecksLens(plan.checksLens)
        if modeChanged {
            logger.log(category: "resources", "\(plan.mode.title): camera \(plan.cameraFrameRate.map { "\($0) FPS" } ?? "default rate"), \(plan.framesInFlight) frame\(plan.framesInFlight == 1 ? "" : "s") in flight")
        }
        if status == .running { reportScanningState() }
    }

    /// Tells MetricKit the app is scanning and with which setup, so daily reports can split it out.
    private func reportScanningState() {
        AppActivity.scanning(ScanningSetup(
            computeUnits: engine.activeComputeUnits?.rawValue ?? "unknown",
            fastPrediction: engine.activeOptions?.fastPrediction ?? false,
            framesInFlight: resourcePlan.framesInFlight,
            cameraFrameRate: resourcePlan.cameraFrameRate ?? 0,
            resourceMode: resourcePlan.mode.rawValue
        ))
    }

    /// Two smudged readings in a row raise the warning; a clearly clean one drops it.
    private func handleLensCheck(_ confidence: Float) {
        if confidence >= LensInspector.smudgedThreshold {
            smudgedChecks += 1
            if smudgedChecks >= 2, !isLensSmudged {
                isLensSmudged = true
                logger.log(.warning, category: "camera", "Lens looks smudged (\(Int(confidence * 100))% confidence)")
            }
        } else if confidence < LensInspector.clearThreshold {
            smudgedChecks = 0
            isLensSmudged = false
        }
    }

    // MARK: - Lifecycle

    /// Current geofence verdict for the active field.
    var geofenceStatus: GeofenceStatus? {
        field.map { geofence.status(for: $0.region, location: location.lastLocation) }
    }

    /// Logging is paused outside the field unless the user explicitly allowed it.
    var isLoggingBlockedByGeofence: Bool {
        guard geofenceStatus?.presence == .outside else { return false }
        return AppSettings.strictGeofence || !allowsLoggingOutsideField
    }

    func start(field: Field) async {
        if self.field?.id != field.id {
            stop()
            allowsLoggingOutsideField = false
        }
        self.field = field
        isActive = true
        guard status != .running, status != .starting else { return }

        switch CameraService.authorizationStatus {
        case .authorized:
            break
        case .notDetermined:
            status = .requestingPermission
            guard await CameraService.requestAccess() else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        guard isActive else { status = .idle; return }

        status = .starting
        do {
            capabilities = try await camera.configure(quality: AppSettings.captureQuality)
            captureDevice = camera.device
        } catch {
            status = .unavailable(error.localizedDescription)
            logger.log(.error, category: "camera", "Camera unavailable: \(error.localizedDescription)")
            return
        }
        guard isActive else { status = .idle; return }

        // Open paused so the farmer can frame the leaves before detection and logging begin.
        isPaused = true
        camera.setPaused(true)
        camera.start()
        // After configuring, since a new capture format resets the camera frame rate.
        updateResourcePlan(force: true)
        if isTorchOn { camera.setTorch(true) }
        beginSession()
        status = .running
        reportScanningState()
        logger.log(category: "camera", "Scanning started in \(field.name) (\(AppSettings.captureQuality.title))")
    }

    func stop() {
        isActive = false
        guard status == .running else { return }
        camera.stop()
        endSession()
        status = .idle
        AppActivity.idle()
        detections = []
        summary = DetectionSummary()
        stableSeverity = nil
        severityCandidate = nil
        isLensSmudged = false
        smudgedChecks = 0
        latestFrame = nil
        lastFrameAt = nil
        isTorchOn = false
    }

    func togglePause() {
        isPaused.toggle()
        camera.setPaused(isPaused)
        lastFrameAt = nil
        logger.log(category: "camera", isPaused ? "Inference paused" : "Inference resumed")
    }

    func toggleTorch() {
        isTorchOn.toggle()
        camera.setTorch(isTorchOn)
    }

    func setZoom(_ displayFactor: Double) {
        zoom = displayFactor
        camera.setZoom(displayFactor)
    }

    func captureRotationChanged(_ angle: CGFloat) {
        camera.setCaptureRotation(angle)
    }

    /// Saves the most recently analyzed frame with its detections (thesis "Capture & Export Controls").
    func captureSnapshot() {
        guard let latestFrame, !isLoggingBlockedByGeofence else { return }
        record(latestFrame, source: .snapshot)
        snapshotCount += 1
    }

    // MARK: - Frames

    private func handle(_ frame: FrameResult) {
        guard status == .running, !isPaused else { return }

        let now = ContinuousClock.now
        if let lastFrameAt {
            let seconds = lastFrameAt.duration(to: now) / .seconds(1)
            if seconds > 0, seconds < 1 {
                fps = fps == 0 ? 1 / seconds : fps * 0.85 + (1 / seconds) * 0.15
                activeSeconds += seconds
            }
        }
        lastFrameAt = now
        inferenceMs = inferenceMs == 0 ? frame.inferenceMs : inferenceMs * 0.85 + frame.inferenceMs * 0.15

        detections = frame.detections
        imageSize = frame.imageSize
        summary = DetectionSummary(frame.detections)
        latestFrame = frame
        updateStableSeverity(summary.severity)

        frameCount += 1
        inferenceTotalMs += frame.inferenceMs
        peakAphidCount = max(peakAphidCount, summary.aphidCount)

        recordPerformanceSample()
        autoLogIfNeeded(frame)
        healthLogIfNeeded()
    }

    private func updateStableSeverity(_ severity: Severity?) {
        if severity == severityCandidate {
            severityCandidateFrames += 1
        } else {
            severityCandidate = severity
            severityCandidateFrames = 1
        }
        if severityCandidateFrames >= 5, stableSeverity != severity {
            stableSeverity = severity
        }
    }

    private func recordPerformanceSample() {
        let now = Date.now
        if let last = performanceSamples.last, now.timeIntervalSince(last.date) < 0.25 { return }
        performanceSamples.append(PerformanceSample(date: now, fps: fps, latencyMs: inferenceMs))
        if performanceSamples.count > 240 {
            performanceSamples.removeFirst(performanceSamples.count - 240)
        }
    }

    /// Frames the leaf counts must hold for before auto-log saves one: about half a second.
    private static let steadyFramesNeeded = 8

    /// Saves a frame at most once per interval, only after the camera has settled on the same
    /// leaves, and never the same view twice in a row, so holding still on one plant saves one photo.
    private func autoLogIfNeeded(_ frame: FrameResult) {
        guard AppSettings.autoLogEnabled, !frame.detections.isEmpty, !isLoggingBlockedByGeofence else {
            steadyFrames = 0
            return
        }
        if AppSettings.autoLogRequiresAphids, summary.aphidCount == 0 { return }
        if summary == steadySummary {
            steadyFrames += 1
        } else {
            steadySummary = summary
            steadyFrames = 1
        }
        guard steadyFrames >= Self.steadyFramesNeeded,
              Date.now.timeIntervalSince(lastAutoLogAt) >= AppSettings.autoLogInterval,
              !Self.showsSameLeaves(frame.detections, as: lastAutoLogged)
        else { return }
        lastAutoLogAt = .now
        lastAutoLogged = frame.detections
        record(frame, source: .auto)
    }

    /// The same view as the last saved frame: as many leaves, most of them in nearly the same place.
    private static func showsSameLeaves(_ detections: [Detection], as previous: [Detection]) -> Bool {
        guard !previous.isEmpty, detections.count == previous.count else { return false }
        let matched = detections.filter { detection in
            previous.contains { $0.leafClass == detection.leafClass && $0.rect.intersectionOverUnion(with: detection.rect) >= 0.5 }
        }
        return Double(matched.count) >= Double(detections.count) * 0.6
    }

    private func healthLogIfNeeded() {
        guard Date.now.timeIntervalSince(lastHealthLogAt) >= AppSettings.healthLogInterval else { return }
        lastHealthLogAt = .now
        let fpsText = fps.formatted(.number.precision(.fractionLength(1)))
        let latencyText = inferenceMs.formatted(.number.precision(.fractionLength(1)))
        let level: LogLevel = fps > 0 && fps < AppSettings.fpsTarget ? .warning : .info
        logger.log(level, category: "health", "\(fpsText) FPS · \(latencyText) ms inference · \(summary.totalLeaves) leaves in view", fps: fps)
    }

    private func logThermalChange() {
        let level = ThermalLevel(ProcessInfo.processInfo.thermalState)
        logger.log(level >= .serious ? .warning : .info, category: "thermal", "Thermal state changed to \(level.title)", fps: fps)
    }

    // MARK: - Persistence

    private func record(_ frame: FrameResult, source: EventSource) {
        let summary = DetectionSummary(frame.detections)
        let event = DetectionEvent(
            source: source,
            fieldName: field?.name ?? "",
            inferenceMs: frame.inferenceMs,
            imageSize: frame.imageSize,
            summary: summary
        )
        if AppSettings.geotagEnabled, let coordinate = location.lastLocation?.coordinate {
            event.latitude = coordinate.latitude
            event.longitude = coordinate.longitude
        }
        switch geofenceStatus?.presence {
        case .inside: event.geofenceVerified = true
        case .outside: event.geofenceVerified = false
        case .unknown, nil: event.geofenceVerified = nil
        }
        context.insert(event)
        event.session = session
        event.field = field
        event.boxes = frame.detections.map(BoundingBox.init)
        eventsLoggedThisSession += 1

        Task {
            let encoded = await ImageEncoder.encode(frame.frame)
            event.imageData = encoded.image
            event.thumbnailData = encoded.thumbnail
            try? context.save()
        }
    }

    private func beginSession() {
        let session = ScanSession(fieldName: field?.name ?? "", computeUnits: engine.activeComputeUnits?.shortTitle ?? "—")
        context.insert(session)
        session.field = field
        self.session = session
        sessionStartedAt = session.startedAt
        eventsLoggedThisSession = 0
        lastAutoLogged = []
        steadySummary = nil
        steadyFrames = 0
        frameCount = 0
        activeSeconds = 0
        inferenceTotalMs = 0
        peakAphidCount = 0
        fps = 0
        inferenceMs = 0
        lastHealthLogAt = .now
    }

    private func endSession() {
        guard let session else { return }
        session.endedAt = .now
        session.framesProcessed = frameCount
        session.averageFPS = activeSeconds > 0 ? Double(frameCount) / activeSeconds : 0
        session.averageInferenceMs = frameCount > 0 ? inferenceTotalMs / Double(frameCount) : 0
        session.peakAphidCount = peakAphidCount

        if frameCount < 30, session.events.isEmpty {
            context.delete(session)
        } else {
            let fpsText = session.averageFPS.formatted(.number.precision(.fractionLength(1)))
            logger.log(category: "session", "Session ended: \(frameCount) frames, \(fpsText) FPS average, \(session.events.count) events logged", fps: session.averageFPS)
        }
        try? context.save()
        self.session = nil
        sessionStartedAt = nil
    }
}
