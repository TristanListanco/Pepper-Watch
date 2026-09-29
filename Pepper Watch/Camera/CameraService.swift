//
//  CameraService.swift
//  Pepper Watch
//
//  AVFoundation capture → on-device YOLO inference. Frames arrive upright (the rotation
//  coordinator drives the output connection's angle) and are skipped while an inference
//  is still in flight, so the pipeline runs at the model's natural throughput.
//

import AVFoundation
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

    /// Written once on the session queue during configuration.
    private(set) var device: AVCaptureDevice?

    private let continuation: AsyncStream<FrameResult>.Continuation
    private let sessionQueue = DispatchQueue(label: "PepperWatch.camera.session")
    private let videoQueue = DispatchQueue(label: "PepperWatch.camera.video", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()
    private var isConfigured = false

    private struct PipelineState {
        var detector: AphidDetector?
        var isPaused = false
        var inFlight = false
    }

    private let pipeline = Mutex(PipelineState())

    override init() {
        (frames, continuation) = AsyncStream.makeStream(of: FrameResult.self, bufferingPolicy: .bufferingNewest(1))
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
        let detector: AphidDetector? = pipeline.withLock { state in
            guard !state.isPaused, !state.inFlight, let detector = state.detector else { return nil }
            state.inFlight = true
            return detector
        }
        guard let detector else { return }

        let frame = PixelBufferBox(buffer: pixelBuffer)
        Task.detached(priority: .userInitiated) { [self] in
            await analyze(frame, with: detector)
        }
    }

    private func analyze(_ frame: PixelBufferBox, with detector: AphidDetector) async {
        defer { pipeline.withLock { $0.inFlight = false } }
        let clock = ContinuousClock()
        let start = clock.now
        guard let detections = try? await detector.detect(in: frame.buffer) else { return }
        let elapsed = start.duration(to: clock.now) / .milliseconds(1)
        let size = CGSize(width: CVPixelBufferGetWidth(frame.buffer), height: CVPixelBufferGetHeight(frame.buffer))
        continuation.yield(FrameResult(detections: detections, imageSize: size, inferenceMs: elapsed, frame: frame))
    }
}
