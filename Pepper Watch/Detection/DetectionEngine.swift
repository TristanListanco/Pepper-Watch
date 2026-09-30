//
//  DetectionEngine.swift
//  Pepper Watch
//

import CoreGraphics
import CoreML
import Observation

/// Owns the loaded model and publishes a ready-to-use `AphidDetector`.
/// Threshold changes rebuild the request instantly; compute-unit changes reload the model.
@Observable
final class DetectionEngine {
    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var detector: AphidDetector?
    private(set) var modelInfo: ModelInfo?
    private(set) var loadDuration: Duration?
    /// The first prediction after a load, run before scanning so the first camera frame isn't slow.
    private(set) var warmUpDuration: Duration?
    private(set) var activeOptions: ModelLoadOptions?

    var activeComputeUnits: ComputeUnitsOption? { activeOptions?.computeUnits }

    @ObservationIgnored private var loadedModel: LoadedModel?
    @ObservationIgnored private var configuration: DetectorConfiguration?
    @ObservationIgnored private var loadingOptions: ModelLoadOptions?
    @ObservationIgnored private let logger: SystemLogger?

    init(logger: SystemLogger?) {
        self.logger = logger
    }

    func configure(_ newConfiguration: DetectorConfiguration) async {
        guard newConfiguration != configuration || detector == nil else { return }
        configuration = newConfiguration

        var needsWarmUp = false
        if loadedModel?.options != newConfiguration.loadOptions {
            // A load with these options is already running; it applies the latest configuration when done.
            guard loadingOptions != newConfiguration.loadOptions else { return }
            loadingOptions = newConfiguration.loadOptions
            state = .loading
            do {
                let loaded = try await AphidDetector.loadModel(options: newConfiguration.loadOptions)
                guard configuration?.loadOptions == loaded.options else { return }
                loadingOptions = nil
                loadedModel = loaded
                loadDuration = loaded.loadDuration
                activeOptions = loaded.options
                modelInfo = ModelInfo(model: loaded.mlModel, bundleURL: try? AphidDetector.modelURL())
                needsWarmUp = true
                logger?.log(
                    category: "model",
                    "Loaded \(AphidDetector.modelName) on \(loaded.computeUnits.shortTitle)\(loaded.options.fastPrediction ? " (fast prediction)" : "") in \(loaded.loadDuration.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))"
                )
            } catch {
                loadingOptions = nil
                state = .failed(error.localizedDescription)
                logger?.log(.error, category: "model", "Model failed to load: \(error.localizedDescription)")
                return
            }
        }

        guard let loadedModel, let configuration else { return }
        do {
            let detector = try AphidDetector(model: loadedModel, configuration: configuration)
            if needsWarmUp {
                // Core ML finishes preparing the model on its first prediction; do that now
                // rather than on the first camera frame.
                let clock = ContinuousClock()
                let start = clock.now
                _ = try? await detector.detect(in: Self.syntheticImage())
                warmUpDuration = start.duration(to: clock.now)
            }
            self.detector = detector
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
            logger?.log(.error, category: "model", "Could not build detector: \(error.localizedDescription)")
        }
    }

    // MARK: - Benchmark

    struct BenchmarkResult: Equatable {
        var latenciesMs: [Double]
        var computeUnits: ComputeUnitsOption

        var mean: Double { latenciesMs.reduce(0, +) / Double(max(latenciesMs.count, 1)) }
        var standardDeviation: Double {
            guard latenciesMs.count > 1 else { return 0 }
            let mean = mean
            let variance = latenciesMs.reduce(0) { $0 + pow($1 - mean, 2) } / Double(latenciesMs.count - 1)
            return variance.squareRoot()
        }
        var minimum: Double { latenciesMs.min() ?? 0 }
        var maximum: Double { latenciesMs.max() ?? 0 }
        var p95: Double {
            let sorted = latenciesMs.sorted()
            guard !sorted.isEmpty else { return 0 }
            return sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        }
        var impliedFPS: Double { mean > 0 ? 1000 / mean : 0 }
    }

    /// Times repeated inferences on a synthetic 640×640 frame (after warm-up runs).
    /// `progress` is called with the number of timed runs finished so far.
    func runBenchmark(iterations: Int = 50, progress: (Int) -> Void = { _ in }) async throws -> BenchmarkResult? {
        guard let detector, let units = activeComputeUnits else { return nil }
        let image = Self.syntheticImage()
        for _ in 0..<3 { _ = try await detector.detect(in: image) }

        let clock = ContinuousClock()
        var latencies: [Double] = []
        latencies.reserveCapacity(iterations)
        for _ in 0..<iterations {
            let start = clock.now
            _ = try await detector.detect(in: image)
            latencies.append(start.duration(to: clock.now) / .milliseconds(1))
            progress(latencies.count)
        }
        let result = BenchmarkResult(latenciesMs: latencies, computeUnits: units)
        logger?.log(
            category: "benchmark",
            "\(iterations) runs on \(units.shortTitle): mean \(result.mean.formatted(.number.precision(.fractionLength(1)))) ms, SD \(result.standardDeviation.formatted(.number.precision(.fractionLength(1)))) ms (\(result.impliedFPS.formatted(.number.precision(.fractionLength(1)))) FPS)"
        )
        return result
    }

    private static func syntheticImage() -> CGImage {
        let size = 640
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        let colors = [CGColor(red: 0.18, green: 0.45, blue: 0.2, alpha: 1), CGColor(red: 0.55, green: 0.75, blue: 0.3, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])
        return context.makeImage()!
    }
}
