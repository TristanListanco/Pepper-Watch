//
//  Models.swift
//  Pepper Watch
//
//  SwiftData schema mirroring the thesis ERD (Section 3.3.2.1):
//  Detection_Event 1—* Bounding_Box, plus System_Log for health metrics.
//  ScanSession groups a scanning run and keeps its performance numbers.
//

import CoreGraphics
import Foundation
import SwiftData

nonisolated enum EventSource: String, CaseIterable, Codable, Sendable {
    case auto
    case snapshot
    case photo
    case demo

    var title: String {
        switch self {
        case .auto: "Auto-logged"
        case .snapshot: "Snapshot"
        case .photo: "Photo import"
        case .demo: "Demo data"
        }
    }

    var symbol: String {
        switch self {
        case .auto: "timer"
        case .snapshot: "camera.shutter.button"
        case .photo: "photo"
        case .demo: "wand.and.stars"
        }
    }
}

nonisolated enum Verdict: String, Codable, Sendable {
    case correct
    case incorrect
}

@Model
final class ScanSession {
    var id: UUID = UUID()
    var startedAt: Date = Date.now
    var endedAt: Date?
    var fieldName: String = ""
    var framesProcessed: Int = 0
    var averageFPS: Double = 0
    var averageInferenceMs: Double = 0
    var peakAphidCount: Int = 0
    var computeUnits: String = ""
    var isDemo: Bool = false

    @Relationship(deleteRule: .nullify, inverse: \DetectionEvent.session)
    var events: [DetectionEvent] = []

    init(fieldName: String, computeUnits: String, startedAt: Date = .now) {
        self.fieldName = fieldName
        self.computeUnits = computeUnits
        self.startedAt = startedAt
    }

    var duration: TimeInterval {
        (endedAt ?? .now).timeIntervalSince(startedAt)
    }
}

@Model
final class DetectionEvent {
    var id: UUID = UUID()
    var timestamp: Date = Date.now
    var sourceRaw: String = EventSource.snapshot.rawValue
    var fieldName: String = ""
    var inferenceMs: Double = 0
    var imageWidth: Double = 0
    var imageHeight: Double = 0
    var latitude: Double?
    var longitude: Double?
    var notes: String = ""
    // Denormalized so dashboards can aggregate without faulting every box.
    var aphidCount: Int = 0
    var healthyCount: Int = 0

    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?

    var session: ScanSession?

    @Relationship(deleteRule: .cascade, inverse: \BoundingBox.event)
    var boxes: [BoundingBox] = []

    init(
        timestamp: Date = .now,
        source: EventSource,
        fieldName: String,
        inferenceMs: Double,
        imageSize: CGSize,
        summary: DetectionSummary
    ) {
        self.timestamp = timestamp
        self.sourceRaw = source.rawValue
        self.fieldName = fieldName
        self.inferenceMs = inferenceMs
        self.imageWidth = imageSize.width
        self.imageHeight = imageSize.height
        self.aphidCount = summary.aphidCount
        self.healthyCount = summary.healthyCount
    }

    var source: EventSource { EventSource(rawValue: sourceRaw) ?? .snapshot }
    var summary: DetectionSummary { DetectionSummary(aphidCount: aphidCount, healthyCount: healthyCount) }
    var severity: Severity? { summary.severity }
    var imageSize: CGSize { CGSize(width: imageWidth, height: imageHeight) }

    var coordinate: (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        return (latitude, longitude)
    }

    var detections: [Detection] {
        boxes.map(\.detection).sorted { $0.confidence > $1.confidence }
    }
}

@Model
final class BoundingBox {
    var id: UUID = UUID()
    var labelRaw: String = LeafClass.healthy.rawValue
    var confidence: Double = 0
    var x: Double = 0
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
    /// Set when a user confirms or rejects the prediction in History (field validation).
    var verdictRaw: String?

    var event: DetectionEvent?

    init(_ detection: Detection) {
        self.id = detection.id
        self.labelRaw = detection.leafClass.rawValue
        self.confidence = detection.confidence
        self.x = detection.rect.minX
        self.y = detection.rect.minY
        self.width = detection.rect.width
        self.height = detection.rect.height
    }

    var leafClass: LeafClass { LeafClass(rawValue: labelRaw) ?? .healthy }

    var verdict: Verdict? {
        get { verdictRaw.flatMap(Verdict.init(rawValue:)) }
        set { verdictRaw = newValue?.rawValue }
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    var detection: Detection {
        Detection(id: id, leafClass: leafClass, confidence: confidence, rect: rect)
    }
}

nonisolated enum LogLevel: String, CaseIterable, Codable, Sendable {
    case info
    case warning
    case error

    var symbol: String {
        switch self {
        case .info: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }
}

@Model
final class SystemLog {
    var timestamp: Date = Date.now
    var levelRaw: String = LogLevel.info.rawValue
    var category: String = ""
    var message: String = ""
    var thermalState: String = ""
    var memoryMB: Double = 0
    var batteryPercent: Double = -1
    var fps: Double = 0

    init(level: LogLevel, category: String, message: String, metrics: DeviceMetrics.Snapshot, fps: Double = 0) {
        self.levelRaw = level.rawValue
        self.category = category
        self.message = message
        self.thermalState = metrics.thermalState.title
        self.memoryMB = metrics.memoryMB
        self.batteryPercent = metrics.batteryPercent
        self.fps = fps
    }

    var level: LogLevel { LogLevel(rawValue: levelRaw) ?? .info }
}
