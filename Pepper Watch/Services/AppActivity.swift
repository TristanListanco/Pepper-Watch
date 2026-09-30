//
//  AppActivity.swift
//  Pepper Watch
//
//  Tells MetricKit (iOS 27 state reporting) when the app is scanning and how, so daily metric
//  reports split CPU, GPU, memory and location time between scanning and everything else.
//

import StateReporting

/// Describes a scanning setup; MetricKit groups the scanning metrics by these values.
@ReportableMetadata
nonisolated struct ScanningSetup: Equatable, Sendable {
    var computeUnits: String
    var fastPrediction: Bool
    var framesInFlight: Int
    /// 0 when the camera runs at its default rate.
    var cameraFrameRate: Int
    var resourceMode: String
}

nonisolated enum AppActivity {
    static let domain = "com.tristanlistanco.Pepper-Watch.activity"
    static let scanningLabel = "scanning"

    private static let reporter = StateReporter<ScanningSetup, Never>.reporter(for: domain, stableMetadata: ScanningSetup.self)

    static func scanning(_ setup: ScanningSetup) {
        reporter.reportTransition(to: scanningLabel, stableMetadata: setup)
    }

    static func idle() {
        reporter.reportTransition(to: nil)
    }
}
