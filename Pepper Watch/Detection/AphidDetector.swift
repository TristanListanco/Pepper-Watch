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
    /// Ask Core ML to specialize the model for the lowest prediction latency.
    var fastPrediction: Bool

    var loadOptions: ModelLoadOptions {
        ModelLoadOptions(computeUnits: computeUnits, fastPrediction: fastPrediction)
    }
}

/// Everything that needs a model reload when it changes; thresholds don't.
nonisolated struct ModelLoadOptions: Equatable, Sendable {
    var computeUnits: ComputeUnitsOption
    var fastPrediction: Bool

    /// The Core ML configuration for these options, shared by loading and the compute plan.
    var mlConfiguration: MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits.mlComputeUnits
        // FP16 accumulation on the GPU path; the model is FP16 already, so accuracy is unchanged.
        configuration.allowLowPrecisionAccumulationOnGPU = true
        var hints = MLOptimizationHints()
        // Camera frames are always scaled to the same 640×640 input.
        hints.reshapeFrequency = .infrequent
        // Newer Neural Engines benefit most: a slower first load buys lower per-frame latency.
        hints.specializationStrategy = fastPrediction ? .fastPrediction : .default
        configuration.optimizationHints = hints
        return configuration
    }
}

/// A compiled model loaded with particular options.
/// `MLModel` is not annotated `Sendable`, but predictions on a loaded model are thread-safe.
nonisolated final class LoadedModel: @unchecked Sendable {
    let mlModel: MLModel
    let options: ModelLoadOptions
    let loadDuration: Duration

    var computeUnits: ComputeUnitsOption { options.computeUnits }

    init(mlModel: MLModel, options: ModelLoadOptions, loadDuration: Duration) {
        self.mlModel = mlModel
        self.options = options
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

    @concurrent static func loadModel(options: ModelLoadOptions) async throws -> LoadedModel {
        let url = try modelURL()
        let clock = ContinuousClock()
        let start = clock.now
        let model = try await MLModel.load(contentsOf: url, configuration: options.mlConfiguration)
        return LoadedModel(mlModel: model, options: options, loadDuration: start.duration(to: clock.now))
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
