//
//  DemoDataGenerator.swift
//  Pepper Watch
//
//  Synthetic field data so dashboards can be demoed without a live pepper field.
//  Every generated record is tagged `.demo` and can be removed separately.
//

import SwiftData
import UIKit

enum DemoDataGenerator {
    /// Claveria, Misamis Oriental: one of the Northern Mindanao growing areas cited in the thesis.
    private static let fieldCenter = (latitude: 8.6107, longitude: 124.8947)
    private static let fieldNames = ["Field A", "Field B", "Greenhouse 1"]

    static func generate(in context: ModelContext, days: Int = 14) {
        var rng = SystemRandomNumberGenerator()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let fields = demoFields(in: context)

        for dayOffset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            let progress = 1 - Double(dayOffset) / Double(max(days - 1, 1))
            // Infestation builds up, then drops after a treatment three days before today.
            let baseRate = dayOffset <= 2 ? 0.12 + Double(dayOffset) * 0.04 : 0.08 + progress * 0.45

            for field in fields.shuffled().prefix(Int.random(in: 1...2, using: &rng)) {
                let start = day.addingTimeInterval(Double.random(in: 6.5...15, using: &rng) * 3600)
                let session = ScanSession(fieldName: field.name, computeUnits: ComputeUnitsOption.all.shortTitle, startedAt: start)
                session.isDemo = true
                session.averageFPS = Double.random(in: 21...32, using: &rng)
                session.averageInferenceMs = Double.random(in: 16...34, using: &rng)
                context.insert(session)
                session.field = field

                let eventCount = Int.random(in: 3...6, using: &rng)
                var frames = 0
                for index in 0..<eventCount {
                    let rate = min(max(baseRate + Double.random(in: -0.12...0.12, using: &rng), 0), 0.95)
                    let event = makeEvent(field: field, at: start.addingTimeInterval(Double(index) * 45), rate: rate, rng: &rng)
                    context.insert(event)
                    event.session = session
                    event.field = field
                    session.peakAphidCount = max(session.peakAphidCount, event.aphidCount)
                    frames += Int.random(in: 400...900, using: &rng)
                }
                session.framesProcessed = frames
                session.endedAt = start.addingTimeInterval(Double(eventCount) * 45 + 30)
            }
        }

        let metrics = DeviceMetrics.snapshot()
        context.insert(SystemLog(level: .info, category: "demo", message: "Generated \(days) days of demo detections", metrics: metrics))
        try? context.save()
    }

    static func removeDemoData(in context: ModelContext) {
        let demo = EventSource.demo.rawValue
        // Delete one by one so cascade rules remove each event's bounding boxes.
        let events = (try? context.fetch(FetchDescriptor<DetectionEvent>(predicate: #Predicate { $0.sourceRaw == demo }))) ?? []
        for event in events { context.delete(event) }
        let sessions = (try? context.fetch(FetchDescriptor<ScanSession>(predicate: #Predicate { $0.isDemo }))) ?? []
        for session in sessions { context.delete(session) }
        let fields = (try? context.fetch(FetchDescriptor<Field>(predicate: #Predicate { $0.isDemo }))) ?? []
        for field in fields { context.delete(field) }
        try? context.save()
    }

    /// Reuses existing demo fields so generating twice doesn't duplicate them.
    private static func demoFields(in context: ModelContext) -> [Field] {
        let existing = (try? context.fetch(FetchDescriptor<Field>(predicate: #Predicate { $0.isDemo }))) ?? []
        return fieldNames.enumerated().map { index, name in
            if let field = existing.first(where: { $0.name == name }) { return field }
            let field = Field(
                name: name,
                locationName: "Claveria, Misamis Oriental",
                latitude: fieldCenter.latitude + Double(index) * 0.0012,
                longitude: fieldCenter.longitude + Double(index) * 0.0009,
                radiusMeters: index == 2 ? 60 : 110
            )
            field.isDemo = true
            context.insert(field)
            return field
        }
    }

    private static func makeEvent(field: Field, at date: Date, rate: Double, rng: inout SystemRandomNumberGenerator) -> DetectionEvent {
        let leafCount = Int.random(in: 3...10, using: &rng)
        var detections: [Detection] = []
        let columns = 4
        let rows = Int(ceil(Double(leafCount) / Double(columns)))
        for index in 0..<leafCount {
            let isAphid = Double.random(in: 0...1, using: &rng) < rate
            let cellWidth = 1 / Double(columns)
            let cellHeight = 1 / Double(rows)
            let column = Double(index % columns)
            let row = Double(index / columns)
            let width = cellWidth * Double.random(in: 0.65...0.9, using: &rng)
            let height = cellHeight * Double.random(in: 0.6...0.85, using: &rng)
            let rect = CGRect(
                x: column * cellWidth + (cellWidth - width) / 2,
                y: row * cellHeight + (cellHeight - height) / 2,
                width: width,
                height: height
            )
            let confidence = isAphid ? Double.random(in: 0.32...0.94, using: &rng) : Double.random(in: 0.55...0.97, using: &rng)
            detections.append(Detection(leafClass: isAphid ? .aphidInfested : .healthy, confidence: confidence, rect: rect))
        }

        let imageSize = CGSize(width: 720, height: 960)
        let event = DetectionEvent(
            timestamp: date,
            source: .demo,
            fieldName: field.name,
            inferenceMs: Double.random(in: 16...34, using: &rng),
            imageSize: imageSize,
            summary: DetectionSummary(detections)
        )
        // Scatter points inside the field's geofence (~0.00045° ≈ 50 m).
        event.latitude = field.latitude + Double.random(in: -0.00045...0.00045, using: &rng)
        event.longitude = field.longitude + Double.random(in: -0.00045...0.00045, using: &rng)
        event.geofenceVerified = true

        let image = renderLeaves(detections, size: imageSize)
        event.imageData = image.jpegData(compressionQuality: 0.7)
        event.thumbnailData = image.preparingThumbnail(of: CGSize(width: 270, height: 360))?.jpegData(compressionQuality: 0.6)

        event.boxes = detections.map { detection in
            let box = BoundingBox(detection)
            // About 40% of boxes carry a field-validation verdict.
            if Double.random(in: 0...1, using: &rng) < 0.4 {
                let accuracy = detection.leafClass == .aphidInfested ? 0.86 : 0.93
                box.verdict = Double.random(in: 0...1, using: &rng) < accuracy ? .correct : .incorrect
            }
            return box
        }
        return event
    }

    /// Stylized canopy: leaves as ellipses, infested ones yellowed and dotted with aphids.
    private static func renderLeaves(_ detections: [Detection], size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            UIColor(red: 0.09, green: 0.2, blue: 0.1, alpha: 1).setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            for detection in detections {
                let rect = CGRect(
                    x: detection.rect.minX * size.width,
                    y: detection.rect.minY * size.height,
                    width: detection.rect.width * size.width,
                    height: detection.rect.height * size.height
                ).insetBy(dx: 6, dy: 6)
                let infested = detection.leafClass == .aphidInfested
                (infested ? UIColor(red: 0.62, green: 0.66, blue: 0.24, alpha: 1) : UIColor(red: 0.24, green: 0.56, blue: 0.24, alpha: 1)).setFill()
                cg.fillEllipse(in: rect)
                UIColor(white: 1, alpha: 0.25).setStroke()
                cg.setLineWidth(2)
                cg.move(to: CGPoint(x: rect.midX, y: rect.minY + 8))
                cg.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 8))
                cg.strokePath()

                if infested {
                    UIColor(red: 0.16, green: 0.18, blue: 0.08, alpha: 0.9).setFill()
                    for _ in 0..<14 {
                        let dot = CGRect(
                            x: rect.midX + CGFloat.random(in: -rect.width / 3...rect.width / 3),
                            y: rect.midY + CGFloat.random(in: -rect.height / 3...rect.height / 3),
                            width: 5, height: 4
                        )
                        cg.fillEllipse(in: dot)
                    }
                }
            }
        }
    }
}
