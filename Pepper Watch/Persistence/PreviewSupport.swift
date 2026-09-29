//
//  PreviewSupport.swift
//  Pepper Watch
//

import SwiftData

/// In-memory store with sample data for SwiftUI previews.
enum PreviewSupport {
    static let container: ModelContainer = {
        let schema = Schema([ScanSession.self, DetectionEvent.self, BoundingBox.self, SystemLog.self])
        let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        DemoDataGenerator.generate(in: container.mainContext, days: 14)
        return container
    }()

    static let logger = SystemLogger(context: container.mainContext)
    static let engine = DetectionEngine(logger: logger)
    static let location = LocationProvider()
    static let scanner = ScanModel(context: container.mainContext, engine: engine, logger: logger, location: location)
}
