//
//  LensInspector.swift
//  Pepper Watch
//
//  Vision's lens smudge detection (iOS 26). A smudged or dusty lens blurs leaves and hides
//  early aphid damage, so scanning checks every few seconds and asks the farmer to wipe it.
//

import CoreML
import CoreVideo
import Synchronization
import Vision

nonisolated enum LensInspector {
    /// Confidence at or above this counts as smudged.
    static let smudgedThreshold: Float = 0.85
    /// Confidence below this clears the warning; the gap keeps it from flickering.
    static let clearThreshold: Float = 0.6

    /// Pinned to the GPU so it never competes with the aphid model on the Neural Engine.
    private static let gpuRequest: DetectLensSmudgeRequest? = {
        guard let gpu = MLComputeDevice.allComputeDevices.first(where: { if case .gpu = $0 { true } else { false } }) else { return nil }
        var request = DetectLensSmudgeRequest()
        request.setComputeDevice(gpu, for: .main)
        return request
    }()

    /// Set when this device can't run the check on the GPU; Vision then picks the device.
    private static let usesDefaultDevice = Mutex(false)

    /// How likely the lens is smudged (0…1), or `nil` when the check couldn't run.
    @concurrent static func smudgeConfidence(in pixelBuffer: CVPixelBuffer) async -> Float? {
        if !usesDefaultDevice.withLock({ $0 }), let gpuRequest {
            if let observation = try? await gpuRequest.perform(on: pixelBuffer, orientation: .up) {
                return observation.confidence
            }
            usesDefaultDevice.withLock { $0 = true }
        }
        return try? await DetectLensSmudgeRequest().perform(on: pixelBuffer, orientation: .up).confidence
    }
}
