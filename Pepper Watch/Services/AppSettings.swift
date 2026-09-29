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
    static let fieldName = "field.name"
    static let fpsTarget = "benchmark.fpsTarget"
}

nonisolated enum AppSettings {
    /// Model-exported NMS defaults (see the Core ML metadata) and the thesis 17 FPS target.
    nonisolated(unsafe) static let defaults: [String: Any] = [
        SettingsKey.confidenceThreshold: 0.25,
        SettingsKey.iouThreshold: 0.7,
        SettingsKey.computeUnits: ComputeUnitsOption.all.rawValue,
        SettingsKey.classAgnosticNMS: true,
        SettingsKey.captureQuality: CaptureQuality.hd720.rawValue,
        SettingsKey.showLabels: true,
        SettingsKey.showConfidence: true,
        SettingsKey.showPerformanceHUD: true,
        SettingsKey.hapticsEnabled: true,
        SettingsKey.autoLogEnabled: true,
        SettingsKey.autoLogInterval: 3.0,
        SettingsKey.autoLogRequiresAphids: false,
        SettingsKey.geotagEnabled: true,
        SettingsKey.healthLogInterval: 30.0,
        SettingsKey.fieldName: "Field A",
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
            classAgnosticNMS: store.bool(forKey: SettingsKey.classAgnosticNMS)
        )
    }

    static var captureQuality: CaptureQuality {
        CaptureQuality(rawValue: store.string(forKey: SettingsKey.captureQuality) ?? "") ?? .hd720
    }

    static var autoLogEnabled: Bool { store.bool(forKey: SettingsKey.autoLogEnabled) }
    static var autoLogInterval: Double { store.double(forKey: SettingsKey.autoLogInterval) }
    static var autoLogRequiresAphids: Bool { store.bool(forKey: SettingsKey.autoLogRequiresAphids) }
    static var geotagEnabled: Bool { store.bool(forKey: SettingsKey.geotagEnabled) }
    static var healthLogInterval: Double { store.double(forKey: SettingsKey.healthLogInterval) }
    static var hapticsEnabled: Bool { store.bool(forKey: SettingsKey.hapticsEnabled) }
    static var fieldName: String { store.string(forKey: SettingsKey.fieldName) ?? "Field A" }
    static var fpsTarget: Double { store.double(forKey: SettingsKey.fpsTarget) }
}
