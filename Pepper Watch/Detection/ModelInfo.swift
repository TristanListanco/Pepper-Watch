//
//  ModelInfo.swift
//  Pepper Watch
//

import CoreML
import Foundation

/// Model card details read from the Core ML metadata written by the Ultralytics exporter.
nonisolated struct ModelInfo: Sendable {
    var summary: String
    var author: String
    var version: String
    var license: String
    var task: String
    var exportedAt: String
    var exportArguments: String
    var classNames: [String]
    var inputWidth: Int
    var inputHeight: Int
    var defaultConfidence: Double?
    var defaultIoU: Double?
    var sizeOnDisk: Int64

    init(model: MLModel, bundleURL: URL?) {
        let metadata = model.modelDescription.metadata
        let custom = metadata[.creatorDefinedKey] as? [String: String] ?? [:]

        summary = metadata[.description] as? String ?? "—"
        author = metadata[.author] as? String ?? "—"
        version = metadata[.versionString] as? String ?? "—"
        license = metadata[.license] as? String ?? "—"
        task = custom["task"] ?? "detect"
        exportedAt = custom["date"] ?? "—"
        exportArguments = custom["args"] ?? "—"
        classNames = Self.parseClassNames(custom["names"])
        defaultConfidence = custom["Confidence threshold"].flatMap(Double.init)
        defaultIoU = custom["IoU threshold"].flatMap(Double.init)

        let image = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint
        inputWidth = image?.pixelsWide ?? 640
        inputHeight = image?.pixelsHigh ?? 640

        sizeOnDisk = bundleURL.map(DiskUsage.size(of:)) ?? 0
    }

    /// Parses the Python dict literal `{0: 'aphid_infested', 1: 'healthy'}`.
    static func parseClassNames(_ raw: String?) -> [String] {
        guard let raw else { return LeafClass.allCases.map(\.rawValue) }
        let names = raw.matches(of: /'([^']+)'/).map { String($0.output.1) }
        return names.isEmpty ? LeafClass.allCases.map(\.rawValue) : names
    }
}
