//
//  CSVExport.swift
//  Pepper Watch
//
//  Thesis "Capture & Export Controls": export diagnostic logs as standardized CSV.
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct CSVDocument: Transferable, Sendable {
    let filename: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            Data(document.text.utf8)
        }
        .suggestedFileName { $0.filename }
    }
}

enum CSVExporter {
    /// One row per bounding box, joined with its detection event.
    static func detections(_ events: [DetectionEvent]) -> CSVDocument {
        var lines = [
            "event_id,timestamp,field,source,latitude,longitude,inference_ms,image_width,image_height,aphid_count,healthy_count,infestation_rate,severity,box_id,class,confidence,x,y,width,height,verdict",
        ]
        let iso = ISO8601DateFormatter()
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            let eventColumns = [
                event.id.uuidString,
                iso.string(from: event.timestamp),
                escape(event.fieldName),
                event.source.rawValue,
                event.latitude.map { String($0) } ?? "",
                event.longitude.map { String($0) } ?? "",
                String(format: "%.2f", event.inferenceMs),
                String(Int(event.imageWidth)),
                String(Int(event.imageHeight)),
                String(event.aphidCount),
                String(event.healthyCount),
                String(format: "%.4f", event.summary.infestationRate),
                event.severity?.title ?? "",
            ]
            if event.boxes.isEmpty {
                lines.append((eventColumns + Array(repeating: "", count: 8)).joined(separator: ","))
            }
            for box in event.boxes {
                let boxColumns = [
                    box.id.uuidString,
                    box.labelRaw,
                    String(format: "%.4f", box.confidence),
                    String(format: "%.4f", box.x),
                    String(format: "%.4f", box.y),
                    String(format: "%.4f", box.width),
                    String(format: "%.4f", box.height),
                    box.verdictRaw ?? "",
                ]
                lines.append((eventColumns + boxColumns).joined(separator: ","))
            }
        }
        return CSVDocument(filename: "pepper-watch-detections-\(stamp()).csv", text: lines.joined(separator: "\n"))
    }

    static func systemLogs(_ logs: [SystemLog]) -> CSVDocument {
        var lines = ["timestamp,level,category,message,thermal_state,memory_mb,battery_percent,fps"]
        let iso = ISO8601DateFormatter()
        for log in logs.sorted(by: { $0.timestamp < $1.timestamp }) {
            lines.append([
                iso.string(from: log.timestamp),
                log.levelRaw,
                escape(log.category),
                escape(log.message),
                log.thermalState,
                String(format: "%.1f", log.memoryMB),
                log.batteryPercent < 0 ? "" : String(format: "%.0f", log.batteryPercent),
                String(format: "%.2f", log.fps),
            ].joined(separator: ","))
        }
        return CSVDocument(filename: "pepper-watch-system-log-\(stamp()).csv", text: lines.joined(separator: "\n"))
    }

    static func sessions(_ sessions: [ScanSession]) -> CSVDocument {
        var lines = ["session_id,started_at,ended_at,field,frames_processed,average_fps,average_inference_ms,peak_aphid_count,compute_units,events"]
        let iso = ISO8601DateFormatter()
        for session in sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            lines.append([
                session.id.uuidString,
                iso.string(from: session.startedAt),
                session.endedAt.map(iso.string(from:)) ?? "",
                escape(session.fieldName),
                String(session.framesProcessed),
                String(format: "%.2f", session.averageFPS),
                String(format: "%.2f", session.averageInferenceMs),
                String(session.peakAphidCount),
                escape(session.computeUnits),
                String(session.events.count),
            ].joined(separator: ","))
        }
        return CSVDocument(filename: "pepper-watch-sessions-\(stamp()).csv", text: lines.joined(separator: "\n"))
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func stamp() -> String {
        Date.now.formatted(.iso8601.year().month().day())
    }
}
