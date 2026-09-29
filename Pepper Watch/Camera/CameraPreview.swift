//
//  CameraPreview.swift
//  Pepper Watch
//

import AVFoundation
import SwiftUI

/// Hosts `AVCaptureVideoPreviewLayer` and keeps preview and analyzed frames level with the horizon.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let device: AVCaptureDevice?
    let onCaptureRotationChange: (CGFloat) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onCaptureRotationChange = onCaptureRotationChange
        view.attach(device: device)
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.onCaptureRotationChange = onCaptureRotationChange
        view.attach(device: device)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    var onCaptureRotationChange: ((CGFloat) -> Void)?

    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var observations: [NSKeyValueObservation] = []
    private weak var attachedDevice: AVCaptureDevice?

    func attach(device: AVCaptureDevice?) {
        guard let device, device !== attachedDevice else { return }
        attachedDevice = device

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        onCaptureRotationChange?(coordinator.videoRotationAngleForHorizonLevelCapture)

        observations = [
            coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { @Sendable [weak self] _, change in
                guard let angle = change.newValue, let self else { return }
                Task { @MainActor in self.applyPreviewRotation(angle) }
            },
            coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: .new) { @Sendable [weak self] _, change in
                guard let angle = change.newValue, let self else { return }
                Task { @MainActor in self.onCaptureRotationChange?(angle) }
            },
        ]
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
