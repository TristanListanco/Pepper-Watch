//
//  DeviceMetrics.swift
//  Pepper Watch
//
//  Phone equivalent of the thesis "System Health Monitor": thermal state stands in for
//  the Raspberry Pi CPU temperature, alongside memory footprint and battery.
//

import Darwin
import Observation
import UIKit

nonisolated enum ThermalLevel: Int, Comparable, Sendable {
    case nominal, fair, serious, critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .nominal
        }
    }

    static func < (lhs: ThermalLevel, rhs: ThermalLevel) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        }
    }

    var symbol: String {
        switch self {
        case .nominal: "thermometer.low"
        case .fair: "thermometer.medium"
        case .serious, .critical: "thermometer.high"
        }
    }

    /// Mapped onto the reserved status palette.
    var severity: Severity {
        switch self {
        case .nominal: .clear
        case .fair: .low
        case .serious: .moderate
        case .critical: .severe
        }
    }
}

enum DeviceMetrics {
    nonisolated struct Snapshot: Sendable {
        var thermalState: ThermalLevel
        var memoryMB: Double
        /// 0...100, or -1 when unavailable (Simulator).
        var batteryPercent: Double
    }

    static func snapshot() -> Snapshot {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let battery = device.batteryLevel
        return Snapshot(
            thermalState: ThermalLevel(ProcessInfo.processInfo.thermalState),
            memoryMB: memoryFootprintMB(),
            batteryPercent: battery < 0 ? -1 : Double(battery) * 100
        )
    }

    /// Physical memory footprint, the same figure Xcode's memory gauge shows.
    nonisolated static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}

/// Polls device health while a view that shows it is on screen.
@Observable
final class DeviceMonitor {
    private(set) var snapshot = DeviceMetrics.snapshot()
    private(set) var memoryHistory: [MemorySample] = []

    struct MemorySample: Identifiable {
        let id = UUID()
        let date: Date
        let megabytes: Double
    }

    /// Call from `.task {}` so polling stops when the view disappears.
    func monitor(every interval: Duration = .seconds(2)) async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: interval)
        }
    }

    func refresh() {
        snapshot = DeviceMetrics.snapshot()
        // Two screens can poll at once (the Developer summary and the monitor); keep one sample a second.
        if let last = memoryHistory.last, Date.now.timeIntervalSince(last.date) < 1 { return }
        memoryHistory.append(MemorySample(date: .now, megabytes: snapshot.memoryMB))
        if memoryHistory.count > 90 { memoryHistory.removeFirst(memoryHistory.count - 90) }
    }
}
