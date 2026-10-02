//
//  ScanReport.swift
//  Pepper Watch
//
//  One-page PDF of a scan for the share sheet.
//

import SwiftUI

enum ScanReport {
    /// Renders the report to a PDF in the temporary directory and returns its URL.
    static func renderPDF(for event: DetectionEvent, insight: ScanInsight?) -> URL? {
        let pageWidth: CGFloat = 612 // US Letter width in points
        let renderer = ImageRenderer(
            content: ScanReportView(event: event, insight: insight)
                .frame(width: pageWidth)
                .environment(\.colorScheme, .light)
        )
        let field = event.fieldName.isEmpty ? "Scan" : event.fieldName
        let name = "Pepper Watch – \(field) – \(event.timestamp.formatted(.dateTime.year().month().day().hour().minute()))"
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
        let url = URL.temporaryDirectory.appending(path: "\(name).pdf")

        var rendered = false
        renderer.render { size, draw in
            var mediaBox = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            rendered = true
        }
        return rendered ? url : nil
    }
}

private struct ScanReportView: View {
    let event: DetectionEvent
    let insight: ScanInsight?

    var body: some View {
        let summary = event.summary
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(alignment: .firstTextBaseline) {
                Label("Pepper Watch", systemImage: "leaf.fill")
                    .font(.headline)
                    .foregroundStyle(Color(.accent))
                Spacer()
                Text("Scan Report")
                    .font(.headline)
                    .foregroundStyle(.secondaryText)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.fieldName.isEmpty ? "Unassigned scan" : event.fieldName)
                    .font(.title.weight(.bold))
                Text(event.timestamp.formatted(date: .complete, time: .shortened))
                    .foregroundStyle(.secondaryText)
                if let verified = event.geofenceVerified {
                    Label(verified ? "Taken inside the field boundary" : "Taken outside the field boundary", systemImage: verified ? "checkmark.seal" : "location.slash")
                        .font(.caption)
                        .foregroundStyle(.secondaryText)
                }
            }

            // Result
            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    SeverityBadge(severity: summary.severity)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(summary.infestationRate.percentText)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        Text("infested")
                            .font(.title3)
                            .foregroundStyle(.secondaryText)
                    }
                }
                Spacer()
                reportStat(summary.aphidCount, LeafClass.aphidInfested)
                reportStat(summary.healthyCount, LeafClass.healthy)
            }
            .padding()
            .background((summary.severity?.color ?? .gray).opacity(0.12), in: .rect(cornerRadius: 16))

            AnnotatedImageView(imageData: event.imageData, detections: event.detections)
                .clipShape(.rect(cornerRadius: 12))

            if let insight {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Insight").font(.headline)
                    Text(insight.headline).font(.title3.weight(.semibold))
                    ForEach(insight.observations, id: \.self) { Text("• \($0)") }
                    if let nextStep = insight.nextStep {
                        Text("Next step: \(nextStep)")
                    }
                    Text(insight.source.footnote)
                        .font(.caption)
                        .foregroundStyle(.secondaryText)
                }
            }

            if let severity = summary.severity {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Guidance: \(severity.headline)").font(.headline)
                    ForEach(Array(severity.recommendations.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                    }
                }
            }

            if !event.boxes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Detections").font(.headline)
                    ForEach(event.boxes.sorted { $0.confidence > $1.confidence }) { box in
                        HStack {
                            Text(box.leafClass.displayName)
                            Spacer()
                            Text(box.confidence.percentText).monospacedDigit()
                                .frame(width: 60, alignment: .trailing)
                            Text(box.verdict == .correct ? "Verified" : box.verdict == .incorrect ? "Rejected" : "—")
                                .frame(width: 80, alignment: .trailing)
                                .foregroundStyle(.secondaryText)
                        }
                        .font(.callout)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Details").font(.headline)
                ForEach(details, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.label)
                            .foregroundStyle(.secondaryText)
                        Spacer()
                        Text(row.value)
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.callout)
                }
            }

            if !event.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").font(.headline)
                    Text(event.notes)
                }
            }

            Text("Generated on device by Pepper Watch. Detections come from an on-device YOLO model trained on bell pepper leaves (aphid-infested vs. healthy). Guidance is general; follow product labels and your local agriculturist's advice.")
                .font(.caption2)
                .foregroundStyle(.secondaryText)
        }
        .padding(36)
        .background(Color.white)
    }

    /// The same metadata shown on the scan's detail page.
    private var details: [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = [
            ("Field", event.fieldName.isEmpty ? "—" : event.fieldName),
            ("Location check", {
                switch event.geofenceVerified {
                case true?: "Inside field boundary"
                case false?: "Outside field boundary"
                case nil: event.source == .photo ? "Photo import" : "Not checked"
                }
            }()),
            ("Source", event.source.title),
            ("Inference", "\(event.inferenceMs.fixed(1)) ms"),
            ("Frame", "\(Int(event.imageWidth)) × \(Int(event.imageHeight)) px"),
        ]
        if let session = event.session {
            rows.append(("Session average", "\(session.averageFPS.fixed(1)) FPS"))
        }
        if let coordinate = event.coordinate {
            rows.append(("Location", "\(coordinate.latitude.fixed(5)), \(coordinate.longitude.fixed(5))"))
        }
        return rows
    }

    private func reportStat(_ count: Int, _ leafClass: LeafClass) -> some View {
        VStack(spacing: 2) {
            Image(systemName: leafClass.symbol)
                .foregroundStyle(leafClass.color)
                .accessibilityHidden(true)
            Text(count, format: .number)
                .font(.title2.weight(.bold))
            Text(leafClass.displayName)
                .font(.caption)
                .foregroundStyle(.secondaryText)
        }
        .accessibilityElement(children: .combine)
    }
}

/// While a scan's details are open, a screenshot offers the scan's PDF report as its "Full Page"
/// option (UIScreenshotService), so the whole report can be marked up and saved from there.
final class ScreenshotReportProvider: NSObject, UIScreenshotServiceDelegate {
    static let shared = ScreenshotReportProvider()
    private var reportURL: URL?

    /// Offers `url` for full-page screenshots, attaching to every window of the app.
    func show(_ url: URL?) {
        reportURL = url
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            scene.screenshotService?.delegate = self
        }
    }

    /// Stops offering `url` once its scan is closed.
    func clear(_ url: URL?) {
        if reportURL == url { reportURL = nil }
    }

    func screenshotService(_ screenshotService: UIScreenshotService, generatePDFRepresentationWithCompletion completionHandler: @escaping (Data?, Int, CGRect) -> Void) {
        // No report open: the screenshot editor shows only the screen.
        completionHandler(reportURL.flatMap { try? Data(contentsOf: $0) }, 0, .zero)
    }
}
