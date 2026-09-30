//
//  CameraService.swift
//  Pepper Watch
//
//  AVFoundation capture → on-device YOLO inference. Frames arrive upright (the rotation
//  coordinator drives the output connection's angle). Up to `maxInFlight` frames are analyzed
//  at once and the rest are skipped, so the pipeline runs at the model's natural throughput:
//  with two in flight, one frame's scaling overlaps the previous frame's Neural Engine work.
//

import AVFoundation
import OSLog
import Synchronization

/// A pixel buffer handed between the capture queue and the main actor.
nonisolated struct PixelBufferBox: @unchecked Sendable {
    let buffer: CVPixelBuffer
}

nonisolated struct FrameResult: Sendable {
    let detections: [Detection]
    let imageSize: CGSize
    let inferenceMs: Double
    let frame: PixelBufferBox
}

nonisolated struct CameraCapabilities: Equatable, Sendable {
    var hasTorch = false
    /// Zoom levels as the user sees them (0.5×, 1×, 2×…).
    var zoomPresets: [Double] = [1]
}

nonisolated enum CameraError: LocalizedError {
    case unavailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .unavailable: "No back camera is available on this device."
        case .cannotAddInput: "The camera input could not be added to the capture session."
        case .cannotAddOutput: "The video output could not be added to the capture session."
        }
    }
}

nonisolated final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let frames: AsyncStream<FrameResult>
    /// Lens smudge confidence (0…1) from periodic checks while scanning.
    let lensChecks: AsyncStream<Float>

    /// Written once on the session queue during configuration.
    private(set) var device: AVCaptureDevice?

    private let continuation: AsyncStream<FrameResult>.Continuation
    private let lensContinuation: AsyncStream<Float>.Continuation
    private let sessionQueue = DispatchQueue(label: "PepperWatch.camera.session")
    private let videoQueue = DispatchQueue(label: "PepperWatch.camera.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false

    /// How often the lens is checked for smudges while scanning.
    private static let lensCheckInterval: Duration = .seconds(4)
    /// Inference and lens-check intervals for Instruments; free when not recording.
    private static let signposter = OSSignposter(subsystem: "com.tristanlistanco.Pepper-Watch", category: "Scanning")

    private struct PipelineState {
        var detector: AphidDetector?
        var isPaused = false
        var inFlight = 0
        var maxInFlight = 1
        /// Frames are numbered so a slower earlier result never replaces a newer one.
        var nextSequence: UInt64 = 0
        var lastDelivered: UInt64 = 0
        var checksLens = true
        var lensCheckInFlight = false
        var lastLensCheck: ContinuousClock.Instant?
    }

    private let pipeline = Mutex(PipelineState())

    override init() {
        (frames, continuation) = AsyncStream.makeStream(of: FrameResult.self, bufferingPolicy: .bufferingNewest(1))
        (lensChecks, lensContinuation) = AsyncStream.makeStream(of: Float.self, bufferingPolicy: .bufferingNewest(1))
        super.init()
    }

    // MARK: - Authorization

    static var authorizationStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    static func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    // MARK: - Session lifecycle

    func configure(quality: CaptureQuality) async throws -> CameraCapabilities {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                do {
                    continuation.resume(returning: try self.configureSession(quality: quality))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func start() {
        sessionQueue.async {
            guard self.isConfigured, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async {
            guard self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    func setDetector(_ detector: AphidDetector?) {
        pipeline.withLock { $0.detector = detector }
    }

    func setPaused(_ paused: Bool) {
        pipeline.withLock { $0.isPaused = paused }
    }

    /// 1 analyzes frames one at a time; 2 overlaps consecutive frames.
    func setMaxInFlight(_ count: Int) {
        pipeline.withLock { $0.maxInFlight = max(1, count) }
    }

    func setChecksLens(_ enabled: Bool) {
        pipeline.withLock { $0.checksLens = enabled }
    }

    /// Caps the camera's frame rate to save power and heat; `nil` restores the default.
    func setFrameRateCap(_ framesPerSecond: Int?) {
        sessionQueue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            defer { device.unlockForConfiguration() }
            if let framesPerSecond,
               device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= Double(framesPerSecond) && Double(framesPerSecond) <= $0.maxFrameRate }) {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
            } else {
                device.activeVideoMinFrameDuration = .invalid
            }
        }
    }

    /// Keeps analyzed frames upright; driven by `AVCaptureDevice.RotationCoordinator`.
    func setCaptureRotation(_ angle: CGFloat) {
        sessionQueue.async {
            guard let connection = self.videoOutput.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle)
            else { return }
            connection.videoRotationAngle = angle
        }
    }

    func setTorch(_ on: Bool) {
        sessionQueue.async {
            guard let device = self.device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
            device.torchMode = on ? .on : .off
            device.unlockForConfiguration()
        }
    }

    /// - Parameter displayFactor: the zoom level shown to the user, e.g. 0.5 or 2.
    func setZoom(_ displayFactor: Double) {
        sessionQueue.async {
            guard let device = self.device, (try? device.lockForConfiguration()) != nil else { return }
            let factor = CGFloat(displayFactor) / device.displayVideoZoomFactorMultiplier
            let clamped = min(max(factor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
            device.ramp(toVideoZoomFactor: clamped, withRate: 8)
            device.unlockForConfiguration()
        }
    }

    private func configureSession(quality: CaptureQuality) throws -> CameraCapabilities {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let preset: AVCaptureSession.Preset = quality == .hd1080 ? .hd1920x1080 : .hd1280x720
        if session.canSetSessionPreset(preset) { session.sessionPreset = preset }

        if !isConfigured {
            // Virtual multi-camera devices switch to the ultra-wide automatically for close-up macro shots.
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
                mediaType: .video,
                position: .back
            )
            guard let device = discovery.devices.first else { throw CameraError.unavailable }

            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
            session.addInput(input)

            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
            guard session.canAddOutput(videoOutput) else { throw CameraError.cannotAddOutput }
            session.addOutput(videoOutput)

            if (try? device.lockForConfiguration()) != nil {
                device.videoZoomFactor = min(max(1 / device.displayVideoZoomFactorMultiplier, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                device.unlockForConfiguration()
            }
            self.device = device
            isConfigured = true
        }

        guard let device else { throw CameraError.unavailable }
        let multiplier = Double(device.displayVideoZoomFactorMultiplier)
        let range = Double(device.minAvailableVideoZoomFactor)...Double(device.maxAvailableVideoZoomFactor)
        let presets = [0.5, 1, 2].filter { range.contains($0 / multiplier) }
        return CameraCapabilities(hasTorch: device.hasTorch, zoomPresets: presets.isEmpty ? [1] : presets)
    }

    // MARK: - Frame analysis

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let now = ContinuousClock.now
        let (job, checksLens): ((AphidDetector, UInt64)?, Bool) = pipeline.withLock { state in
            guard !state.isPaused else { return (nil, false) }
            var job: (AphidDetector, UInt64)?
            if state.inFlight < state.maxInFlight, let detector = state.detector {
                state.inFlight += 1
                state.nextSequence += 1
                job = (detector, state.nextSequence)
            }
            var checksLens = false
            if state.checksLens, !state.lensCheckInFlight,
               state.lastLensCheck.map({ $0.duration(to: now) >= Self.lensCheckInterval }) ?? true {
                state.lensCheckInFlight = true
                state.lastLensCheck = now
                checksLens = true
            }
            return (job, checksLens)
        }

        let frame = PixelBufferBox(buffer: pixelBuffer)
        if let (detector, sequence) = job {
            Task.detached(priority: .userInitiated) { [self] in
                await analyze(frame, sequence: sequence, with: detector)
            }
        }
        if checksLens {
            Task.detached(priority: .utility) { [self] in
                await checkLens(frame)
            }
        }
    }

    private func analyze(_ frame: PixelBufferBox, sequence: UInt64, with detector: AphidDetector) async {
        let signpost = Self.signposter.beginInterval("Inference", id: Self.signposter.makeSignpostID())
        let clock = ContinuousClock()
        let start = clock.now
        let detections = try? await detector.detect(in: frame.buffer)
        let elapsed = start.duration(to: clock.now) / .milliseconds(1)
        Self.signposter.endInterval("Inference", signpost)
        let isNewest = pipeline.withLock { state in
            state.inFlight -= 1
            guard detections != nil, sequence > state.lastDelivered else { return false }
            state.lastDelivered = sequence
            return true
        }
        guard isNewest, let detections else { return }
        let size = CGSize(width: CVPixelBufferGetWidth(frame.buffer), height: CVPixelBufferGetHeight(frame.buffer))
        continuation.yield(FrameResult(detections: detections, imageSize: size, inferenceMs: elapsed, frame: frame))
    }

    private func checkLens(_ frame: PixelBufferBox) async {
        let signpost = Self.signposter.beginInterval("Lens check", id: Self.signposter.makeSignpostID())
        let confidence = await LensInspector.smudgeConfidence(in: frame.buffer)
        Self.signposter.endInterval("Lens check", signpost)
        pipeline.withLock { $0.lensCheckInFlight = false }
        if let confidence { lensContinuation.yield(confidence) }
    }
}
