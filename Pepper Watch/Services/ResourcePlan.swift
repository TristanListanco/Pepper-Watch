//
//  ResourcePlan.swift
//  Pepper Watch
//
//  How much of the device scanning uses right now. A hot phone or Low Power Mode trades a few
//  camera frames for battery and heat, while staying at the thesis's 17 FPS target where it can.
//

import Foundation

nonisolated struct ResourcePlan: Equatable, Sendable {
    enum Mode: String, Sendable {
        case full, lowPower, warm, hot

        var title: String {
            switch self {
            case .full: "Full speed"
            case .lowPower: "Low Power Mode"
            case .warm: "Warm: easing off"
            case .hot: "Hot: cooling down"
            }
        }
    }

    var mode: Mode
    /// Camera frames per second, or `nil` for the camera's default (30).
    var cameraFrameRate: Int?
    var framesInFlight: Int
    var checksLens: Bool

    /// - Parameters:
    ///   - allowsPipelining: the setting is on and there's a Neural Engine to keep busy.
    ///   - lensCheck: the lens smudge check setting.
    static func current(allowsPipelining: Bool, lensCheck: Bool, processInfo: ProcessInfo = .processInfo) -> ResourcePlan {
        let thermal = ThermalLevel(processInfo.thermalState)
        if thermal >= .critical {
            return ResourcePlan(mode: .hot, cameraFrameRate: 12, framesInFlight: 1, checksLens: false)
        }
        if thermal >= .serious {
            return ResourcePlan(mode: .warm, cameraFrameRate: 20, framesInFlight: 1, checksLens: lensCheck)
        }
        if processInfo.isLowPowerModeEnabled {
            return ResourcePlan(mode: .lowPower, cameraFrameRate: 20, framesInFlight: 1, checksLens: false)
        }
        return ResourcePlan(mode: .full, cameraFrameRate: nil, framesInFlight: allowsPipelining ? 2 : 1, checksLens: lensCheck)
    }
}
