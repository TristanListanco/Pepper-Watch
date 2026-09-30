//
//  ComputePlanReport.swift
//  Pepper Watch
//
//  Where Core ML plans to run each operation of the detector, from `MLComputePlan`.
//

import CoreML

/// A summary of the compute plan for one set of load options.
nonisolated struct ComputePlanReport: Equatable, Sendable {
    enum Device: String, CaseIterable, Identifiable, Sendable {
        case neuralEngine = "Neural Engine"
        case gpu = "GPU"
        case cpu = "CPU"

        var id: String { rawValue }
    }

    /// Operations Core ML scheduled, including the NMS stage.
    var operationCount: Int
    /// Share of the work on each device (0…1): by estimated cost, or by operation count when Core ML
    /// gives no estimates (as in the Simulator).
    var costShare: [Device: Double]
    /// Whether `costShare` comes from Core ML's cost estimates.
    var isCostWeighted: Bool
    /// Operator names that run on the CPU or GPU although the Neural Engine is allowed, most frequent first.
    var fallbackOperators: [(name: String, count: Int)]

    static func == (lhs: ComputePlanReport, rhs: ComputePlanReport) -> Bool {
        lhs.operationCount == rhs.operationCount && lhs.costShare == rhs.costShare
            && lhs.fallbackOperators.map(\.name) == rhs.fallbackOperators.map(\.name)
    }

    /// Loads the plan the way the engine loads the model, then walks every operation.
    @concurrent static func load(options: ModelLoadOptions) async throws -> ComputePlanReport {
        let plan = try await MLComputePlan.load(contentsOf: AphidDetector.modelURL(), configuration: options.mlConfiguration)
        let hasNeuralEngine = MLComputeDevice.allComputeDevices.contains { if case .neuralEngine = $0 { true } else { false } }
        let allowsNeuralEngine = options.computeUnits == .all || options.computeUnits == .cpuAndNeuralEngine
        var tally = Tally(neuralEngineAllowed: hasNeuralEngine && allowsNeuralEngine)
        tally.visit(plan.modelStructure, in: plan)
        return tally.report
    }

    private struct Tally {
        let neuralEngineAllowed: Bool
        var operations = 0
        var cost: [Device: Double] = [:]
        var count: [Device: Double] = [:]
        var fallbacks: [String: Int] = [:]

        mutating func visit(_ structure: MLModelStructure, in plan: MLComputePlan) {
            switch structure {
            case .program(let program):
                for function in program.functions.values { visit(function.block, in: plan) }
            case .pipeline(let pipeline):
                for model in pipeline.subModels { visit(model, in: plan) }
            case .neuralNetwork(let network):
                for layer in network.layers {
                    guard let usage = plan.deviceUsage(for: layer) else { continue }
                    record(Self.device(usage.preferred), weight: 1, name: layer.type)
                }
            case .unsupported:
                break
            @unknown default:
                break
            }
        }

        mutating func visit(_ block: MLModelStructure.Program.Block, in plan: MLComputePlan) {
            for operation in block.operations {
                // Constants are folded at load and cost nothing at prediction time.
                if operation.operatorName != "const", let usage = plan.deviceUsage(for: operation) {
                    record(Self.device(usage.preferred), weight: plan.estimatedCost(of: operation)?.weight ?? 0, name: operation.operatorName)
                }
                for nested in operation.blocks { visit(nested, in: plan) }
            }
        }

        mutating func record(_ device: Device, weight: Double, name: String) {
            operations += 1
            cost[device, default: 0] += weight
            count[device, default: 0] += 1
            if neuralEngineAllowed, device != .neuralEngine {
                fallbacks[name, default: 0] += 1
            }
        }

        static func device(_ device: MLComputeDevice) -> Device {
            switch device {
            case .neuralEngine: .neuralEngine
            case .gpu: .gpu
            case .cpu: .cpu
            @unknown default: .cpu
            }
        }

        var report: ComputePlanReport {
            let totalCost = cost.values.reduce(0, +)
            let weights = totalCost > 0 ? cost : count
            let total = weights.values.reduce(0, +)
            return ComputePlanReport(
                operationCount: operations,
                costShare: total > 0 ? weights.mapValues { $0 / total } : [:],
                isCostWeighted: totalCost > 0,
                fallbackOperators: fallbacks.sorted { $0.value > $1.value }.map { (name: $0.key, count: $0.value) }
            )
        }
    }
}
