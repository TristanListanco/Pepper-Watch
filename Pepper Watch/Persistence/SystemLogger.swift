//
//  SystemLogger.swift
//  Pepper Watch
//

import os
import SwiftData
import SwiftUI

/// Writes `SystemLog` rows (thesis System_Log entity) and mirrors them to the unified log.
final class SystemLogger {
    private let context: ModelContext
    private let logger = Logger(subsystem: "com.tristanlistanco.Pepper-Watch", category: "system")

    init(context: ModelContext) {
        self.context = context
    }

    func log(_ level: LogLevel = .info, category: String, _ message: String, fps: Double = 0) {
        switch level {
        case .info: logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warning: logger.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error: logger.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }
        context.insert(SystemLog(level: level, category: category, message: message, metrics: DeviceMetrics.snapshot(), fps: fps))
        try? context.save()
    }
}

extension EnvironmentValues {
    @Entry var systemLogger: SystemLogger?
}
