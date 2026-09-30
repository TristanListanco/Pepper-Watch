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

enum AppSchema {
    static let schema = Schema([Field.self, ScanSession.self, DetectionEvent.self, BoundingBox.self, SystemLog.self])
}

/// A monitored plot with a circular geofence. Scans are verified against it.
@Model
final class Field {
    var id: UUID = UUID()
    var name: String = ""
    /// Human-readable place, e.g. "Poblacion, Claveria". Reverse-geocoded when the field is created.
    var locationName: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var radiusMeters: Double = 100
    var createdAt: Date = Date.now
    var isDemo: Bool = false

    // Optional to-many relationships keep the schema CloudKit-compatible; `originalName` preserved existing data.
    @Relationship(deleteRule: .nullify, originalName: "events", inverse: \DetectionEvent.field)
    var fieldEvents: [DetectionEvent]? = []

    @Relationship(deleteRule: .nullify, originalName: "sessions", inverse: \ScanSession.field)
    var fieldSessions: [ScanSession]? = []

    var events: [DetectionEvent] {
        get { fieldEvents ?? [] }
        set { fieldEvents = newValue }
    }

    var sessions: [ScanSession] {
        get { fieldSessions ?? [] }
        set { fieldSessions = newValue }
    }

    init(name: String, locationName: String, latitude: Double, longitude: Double, radiusMeters: Double) {
        self.name = name
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
    }

    var region: FieldRegion {
        FieldRegion(id: id, name: name, latitude: latitude, longitude: longitude, radiusMeters: radiusMeters)
    }

    /// Renames the field and the name kept on its scans and sessions, so History, Insights and
    /// reports all show the new name. Returns `false` for a blank name.
    @discardableResult
    func rename(to newName: String) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard trimmed != name else { return true }
        name = trimmed
        for event in events { event.fieldName = trimmed }
        for session in sessions { session.fieldName = trimmed }
        return true
    }
}

/// Sendable snapshot of a field's geofence.
nonisolated struct FieldRegion: Hashable, Sendable {
    let id: UUID
    let name: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
}

@Model
final class ScanSession {
    // Sessions are listed newest first.
    #Index<ScanSession>([\.startedAt])

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
    var field: Field?

    @Relationship(deleteRule: .nullify, originalName: "events", inverse: \DetectionEvent.session)
    var sessionEvents: [DetectionEvent]? = []

    var events: [DetectionEvent] {
        get { sessionEvents ?? [] }
        set { sessionEvents = newValue }
    }

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
    // History sections by day and sorts by time; Insights and widgets fetch by date range.
    #Index<DetectionEvent>([\.timestamp], [\.dayKey, \.timestamp])

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
    /// Whether the device was inside the field's geofence when this was logged (`nil` = not checked).
    var geofenceVerified: Bool?
    // Saved image insight, generated once so it isn't recomputed on every visit.
    var insightHeadline: String?
    var insightObservations: [String]?
    var insightNextStep: String?
    var insightSourceRaw: String?
    var insightGeneratedAt: Date?
    // Denormalized so dashboards can aggregate without faulting every box.
    var aphidCount: Int = 0
    var healthyCount: Int = 0
    /// The scan's calendar day when it was logged, like "2026-09-26". Stored because History
    /// sections its query by it, and SwiftData sections by persisted attributes only.
    var dayKey: String = ""

    @Attribute(.externalStorage) var imageData: Data?
    @Attribute(.externalStorage) var thumbnailData: Data?

    var session: ScanSession?
    var field: Field?

    @Relationship(deleteRule: .cascade, originalName: "boxes", inverse: \BoundingBox.event)
    var detectionBoxes: [BoundingBox]? = []

    var boxes: [BoundingBox] {
        get { detectionBoxes ?? [] }
        set { detectionBoxes = newValue }
    }

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
        self.dayKey = Self.dayKey(for: timestamp)
    }

    /// A date's calendar day in the device's time zone.
    static func dayKey(for date: Date) -> String {
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    /// Fills in the day for scans saved before it was stored.
    static func backfillDayKeys(in context: ModelContext) {
        let missing = FetchDescriptor<DetectionEvent>(predicate: #Predicate { $0.dayKey == "" })
        guard let events = try? context.fetch(missing), !events.isEmpty else { return }
        for event in events { event.dayKey = dayKey(for: event.timestamp) }
        try? context.save()
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
    #Index<SystemLog>([\.timestamp])

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
