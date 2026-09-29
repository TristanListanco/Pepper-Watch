//
//  AphidDetector.swift
//  Pepper Watch
//
//  Wraps the exported Ultralytics YOLO pipeline (detector + NMS) with the Swift Vision API.
//

import CoreML
import CoreVideo
import Vision

nonisolated enum ComputeUnitsOption: String, CaseIterable, Identifiable, Sendable {
    case all
    case cpuAndNeuralEngine
    case cpuAndGPU
    case cpuOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All devices"
        case .cpuAndNeuralEngine: "CPU + Neural Engine"
        case .cpuAndGPU: "CPU + GPU"
        case .cpuOnly: "CPU only"
        }
    }

    var shortTitle: String {
        switch self {
        case .all: "All"
        case .cpuAndNeuralEngine: "CPU+ANE"
        case .cpuAndGPU: "CPU+GPU"
        case .cpuOnly: "CPU"
        }
    }

    var mlComputeUnits: MLComputeUnits {
        switch self {
        case .all: .all
        case .cpuAndNeuralEngine: .cpuAndNeuralEngine
        case .cpuAndGPU: .cpuAndGPU
        case .cpuOnly: .cpuOnly
        }
    }
}

nonisolated struct DetectorConfiguration: Equatable, Sendable {
    var confidenceThreshold: Double
    var iouThreshold: Double
    var computeUnits: ComputeUnitsOption
    /// The exported NMS is per-class, so one leaf can come back as both healthy and infested.
    /// When on, overlapping boxes of different classes keep only the most confident one.
    var classAgnosticNMS: Bool
}

/// A compiled model loaded for a particular set of compute units.
/// `MLModel` is not annotated `Sendable`, but predictions on a loaded model are thread-safe.
nonisolated final class LoadedModel: @unchecked Sendable {
    let mlModel: MLModel
    let computeUnits: ComputeUnitsOption
    let loadDuration: Duration

    init(mlModel: MLModel, computeUnits: ComputeUnitsOption, loadDuration: Duration) {
        self.mlModel = mlModel
        self.computeUnits = computeUnits
        self.loadDuration = loadDuration
    }
}

enum DetectorError: LocalizedError {
    case modelNotFound

    var errorDescription: String? {
        switch self {
        case .modelNotFound: "AphidDetector.mlmodelc is missing from the app bundle."
        }
    }
}

/// Immutable, thread-safe detector. A new instance is built whenever thresholds change.
nonisolated final class AphidDetector: @unchecked Sendable {
    static let modelName = "AphidDetector"

    let configuration: DetectorConfiguration
    private let request: CoreMLRequest

    init(model: LoadedModel, configuration: DetectorConfiguration) throws {
        // The exported pipeline accepts optional NMS threshold inputs alongside the image.
        let thresholds = try MLDictionaryFeatureProvider(dictionary: [
            "iouThreshold": MLFeatureValue(double: configuration.iouThreshold),
            "confidenceThreshold": MLFeatureValue(double: configuration.confidenceThreshold),
        ])
        let container = try CoreMLModelContainer(model: model.mlModel, featureProvider: thresholds)
        var request = CoreMLRequest(model: container)
        request.cropAndScaleAction = .scaleToFill
        self.request = request
        self.configuration = configuration
    }

    static func modelURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw DetectorError.modelNotFound
        }
        return url
    }

    @concurrent static func loadModel(computeUnits: ComputeUnitsOption) async throws -> LoadedModel {
        let url = try modelURL()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits.mlComputeUnits
        let clock = ContinuousClock()
        let start = clock.now
        let model = try await MLModel.load(contentsOf: url, configuration: configuration)
        return LoadedModel(mlModel: model, computeUnits: computeUnits, loadDuration: start.duration(to: clock.now))
    }

    /// Runs detection on an upright camera frame.
    @concurrent func detect(in pixelBuffer: CVPixelBuffer) async throws -> [Detection] {
        detections(from: try await request.perform(on: pixelBuffer, orientation: .up))
    }

    /// Runs detection on an upright still image.
    @concurrent func detect(in image: CGImage) async throws -> [Detection] {
        detections(from: try await request.perform(on: image, orientation: .up))
    }

    private func detections(from observations: [any VisionObservation]) -> [Detection] {
        let unit = CGSize(width: 1, height: 1)
        let detections: [Detection] = observations.compactMap { observation in
            // The NMS layer pads labels to 80 classes; only the first two are real.
            guard let object = observation as? RecognizedObjectObservation,
                  let top = object.labels.first,
                  let leafClass = LeafClass(rawValue: top.identifier),
                  Double(top.confidence) >= configuration.confidenceThreshold
            else { return nil }
            return Detection(
                leafClass: leafClass,
                confidence: Double(top.confidence),
                rect: object.boundingBox.toImageCoordinates(unit, origin: .upperLeft)
            )
        }
        .sorted { $0.confidence > $1.confidence }

        guard configuration.classAgnosticNMS else { return detections }
        var kept: [Detection] = []
        for detection in detections where !kept.contains(where: {
            $0.leafClass != detection.leafClass && $0.rect.intersectionOverUnion(with: detection.rect) > configuration.iouThreshold
        }) {
            kept.append(detection)
        }
        return kept
    }
}
