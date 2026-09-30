//
//  CSVExport.swift
//  Pepper Watch
//
//  Thesis "Capture & Export Controls": export diagnostic logs as standardized CSV.
//

import CoreTransferable
import Foundation
import LinkPresentation
import UIKit
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

    /// Writes the CSV to a fresh temporary file named for sharing, off the main thread.
    @concurrent func writeToTemporaryFile() async throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        // Only the latest export is kept around.
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: filename)
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
}

/// Presents the system share sheet from the frontmost view controller. On iPad it points at
/// `sourceRect`, in window coordinates.
enum SharePresenter {
    static func present(_ items: [Any], from sourceRect: CGRect? = nil) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .keyWindow,
            var presenter = window.rootViewController
        else { return }
        while let presented = presenter.presentedViewController { presenter = presented }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            if let sourceRect {
                popover.sourceRect = presenter.view.convert(sourceRect, from: nil)
            } else {
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        presenter.present(controller, animated: true)
    }

    /// Shares a file with a titled header and icon in the share sheet.
    static func present(file url: URL, title: String, symbol: String = "tablecells", from sourceRect: CGRect? = nil) {
        present([SharedFileItem(url: url, title: title, symbol: symbol)], from: sourceRect)
    }
}

/// A shared file described for the share sheet (LinkPresentation): its header shows a short title
/// and icon instead of the generic "Text Document", and Mail gets "Pepper Watch" plus the title.
nonisolated final class SharedFileItem: NSObject, UIActivityItemSource, Sendable {
    let url: URL
    let title: String
    let symbol: String

    init(url: URL, title: String, symbol: String) {
        self.url = url
        self.title = title
        self.symbol = symbol
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        "Pepper Watch \(title)"
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        metadata.originalURL = url
        let configuration = UIImage.SymbolConfiguration(pointSize: 44, weight: .semibold)
        if let icon = UIImage(systemName: symbol, withConfiguration: configuration)?
            .withTintColor(UIColor(named: "AccentColor") ?? .systemGreen, renderingMode: .alwaysOriginal) {
            metadata.iconProvider = NSItemProvider(object: icon)
        }
        return metadata
    }
}

enum CSVExporter {
    /// One row per bounding box, joined with its detection event.
    static func detections(_ events: [DetectionEvent]) -> CSVDocument {
        var lines = [
            "event_id,timestamp,field_id,field,geofence_verified,source,latitude,longitude,inference_ms,image_width,image_height,aphid_count,healthy_count,infestation_rate,severity,box_id,class,confidence,x,y,width,height,verdict",
        ]
        let iso = ISO8601DateFormatter()
        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            let eventColumns = [
                event.id.uuidString,
                iso.string(from: event.timestamp),
                event.field?.id.uuidString ?? "",
                escape(event.fieldName),
                event.geofenceVerified.map { $0 ? "true" : "false" } ?? "",
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
