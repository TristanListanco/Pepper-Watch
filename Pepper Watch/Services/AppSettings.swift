//
//  AppSettings.swift
//  Pepper Watch
//
//  UserDefaults keys for the Developer tab. Views bind with @AppStorage; non-view code
//  reads the registered defaults through `AppSettings`.
//

import Foundation

nonisolated enum CaptureQuality: String, CaseIterable, Identifiable, Sendable {
    case hd720
    case hd1080

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hd720: "720p (faster)"
        case .hd1080: "1080p (sharper snapshots)"
        }
    }
}

nonisolated enum SettingsKey {
    static let confidenceThreshold = "detector.confidenceThreshold"
    static let iouThreshold = "detector.iouThreshold"
    static let computeUnits = "detector.computeUnits"
    static let classAgnosticNMS = "detector.classAgnosticNMS"
    static let fastPrediction = "detector.fastPrediction"
    static let pipelinedInference = "detector.pipelinedInference"
    static let lensSmudgeCheck = "camera.lensSmudgeCheck"
    static let captureQuality = "camera.captureQuality"
    static let showLabels = "overlay.showLabels"
    static let showConfidence = "overlay.showConfidence"
    static let showPerformanceHUD = "overlay.showPerformanceHUD"
    static let hapticsEnabled = "overlay.haptics"
    static let autoLogEnabled = "logging.autoLog"
    static let autoLogInterval = "logging.autoLogInterval"
    static let autoLogRequiresAphids = "logging.autoLogRequiresAphids"
    static let geotagEnabled = "logging.geotag"
    static let healthLogInterval = "logging.healthInterval"
    static let strictGeofence = "field.strictGeofence"
    static let fpsTarget = "benchmark.fpsTarget"
}

nonisolated enum AppSettings {
    /// Model-exported NMS defaults (see the Core ML metadata) and the thesis 17 FPS target.
    nonisolated(unsafe) static let defaults: [String: Any] = [
        SettingsKey.confidenceThreshold: 0.25,
        SettingsKey.iouThreshold: 0.7,
        SettingsKey.computeUnits: ComputeUnitsOption.all.rawValue,
        SettingsKey.classAgnosticNMS: true,
        SettingsKey.fastPrediction: true,
        SettingsKey.pipelinedInference: true,
        SettingsKey.lensSmudgeCheck: true,
        SettingsKey.captureQuality: CaptureQuality.hd720.rawValue,
        SettingsKey.showLabels: true,
        SettingsKey.showConfidence: true,
        SettingsKey.showPerformanceHUD: true,
        SettingsKey.hapticsEnabled: true,
        SettingsKey.autoLogEnabled: true,
        // Long enough that a scan of one row saves a handful of photos, not dozens.
        SettingsKey.autoLogInterval: 10.0,
        SettingsKey.autoLogRequiresAphids: false,
        SettingsKey.geotagEnabled: true,
        SettingsKey.healthLogInterval: 30.0,
        SettingsKey.strictGeofence: false,
        SettingsKey.fpsTarget: 17.0,
    ]

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: defaults)
    }

    private static var store: UserDefaults { .standard }

    static var detectorConfiguration: DetectorConfiguration {
        DetectorConfiguration(
            confidenceThreshold: store.double(forKey: SettingsKey.confidenceThreshold),
            iouThreshold: store.double(forKey: SettingsKey.iouThreshold),
            computeUnits: ComputeUnitsOption(rawValue: store.string(forKey: SettingsKey.computeUnits) ?? "") ?? .all,
            classAgnosticNMS: store.bool(forKey: SettingsKey.classAgnosticNMS),
            fastPrediction: store.bool(forKey: SettingsKey.fastPrediction)
        )
    }

    /// Up to two camera frames in flight on devices with a Neural Engine.
    static var pipelinedInference: Bool { store.bool(forKey: SettingsKey.pipelinedInference) }

    /// Periodic lens smudge check while scanning.
    static var lensSmudgeCheck: Bool { store.bool(forKey: SettingsKey.lensSmudgeCheck) }

    static var captureQuality: CaptureQuality {
        CaptureQuality(rawValue: store.string(forKey: SettingsKey.captureQuality) ?? "") ?? .hd720
    }

    static var autoLogEnabled: Bool { store.bool(forKey: SettingsKey.autoLogEnabled) }
    static var autoLogInterval: Double { store.double(forKey: SettingsKey.autoLogInterval) }
    static var autoLogRequiresAphids: Bool { store.bool(forKey: SettingsKey.autoLogRequiresAphids) }
    static var geotagEnabled: Bool { store.bool(forKey: SettingsKey.geotagEnabled) }
    static var healthLogInterval: Double { store.double(forKey: SettingsKey.healthLogInterval) }
    static var hapticsEnabled: Bool { store.bool(forKey: SettingsKey.hapticsEnabled) }
    static var strictGeofence: Bool { store.bool(forKey: SettingsKey.strictGeofence) }
    static var fpsTarget: Double { store.double(forKey: SettingsKey.fpsTarget) }
}
