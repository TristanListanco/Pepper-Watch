//
//  DetectionDetailView.swift
//  Pepper Watch
//

import MapKit
import SwiftData
import SwiftUI
import TipKit

struct DetectionDetailView: View {
    @Bindable var event: DetectionEvent

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var decodedImage: UIImage?
    @State private var highlightedID: Detection.ID?
    @State private var reportURL: URL?
    @State private var insight: ScanInsight?
    @State private var isGeneratingInsight = false
    @State private var isConfirmingDelete = false
    @State private var isViewingFullScreen = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var sortedBoxes: [BoundingBox] {
        event.boxes.sorted { $0.confidence > $1.confidence }
    }

    /// Changes that should be reflected in the shared PDF.
    private var reportSignature: String {
        "\(insight?.headline ?? "")|\(event.notes)|\(event.boxes.map { $0.verdictRaw ?? "-" }.joined())"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if horizontalSizeClass == .regular {
                    // iPad: photo and insight beside validation and metadata.
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            photo
                            insightCard
                            notes
                        }
                        .frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 16) {
                            details
                            verification
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    photo
                    insightCard
                    details
                    verification
                    notes
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(event.timestamp.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let reportURL {
                    ShareLink(item: reportURL, preview: SharePreview("Pepper Watch scan report", image: Image(systemName: "doc.richtext"))) {
                        Label("Share Report", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button("Share Report", systemImage: "square.and.arrow.up") {}
                        .disabled(true)
                }
            }
            .visibilityPriority(.high)
            ToolbarItem(placement: .primaryAction) {
                Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
            .visibilityPriority(.low)
        }
        .confirmationDialog("Delete this scan?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Scan", role: .destructive) {
                modelContext.delete(event)
                try? modelContext.save()
                dismiss()
            }
        }
        .fullScreenCover(isPresented: $isViewingFullScreen) {
            ZoomableImageViewer(imageData: event.imageData, detections: event.detections)
        }
        .task(id: event.id) {
            if let data = event.imageData { decodedImage = UIImage(data: data) }
            insight = event.savedInsight
            if insight == nil { await generateInsight() }
        }
        .task(id: reportSignature) {
            // Debounce typing in Notes before re-rendering the PDF.
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            reportURL = ScanReport.renderPDF(for: event, insight: insight)
        }
        .onDisappear { try? modelContext.save() }
    }

    // MARK: - Insight

    private var insightCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Insight").font(.headline)
                Spacer()
                if isGeneratingInsight {
                    ProgressView().controlSize(.small)
                } else if insight != nil {
                    Button("Regenerate", systemImage: "arrow.clockwise") {
                        Task { await generateInsight() }
                    }
                    .labelStyle(.iconOnly)
                }
            }
            if let insight {
                Text(insight.headline)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(insight.observations, id: \.self) { observation in
                    Text(observation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Analyzing this photo…")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.card, in: .rect(cornerRadius: 24))
        .animation(.smooth, value: insight)
    }

    private func generateInsight() async {
        isGeneratingInsight = true
        defer { isGeneratingInsight = false }
        let result = await ScanInsightGenerator.generate(
            image: decodedImage?.cgImage,
            detections: event.detections,
            fieldName: event.fieldName,
            date: event.timestamp
        )
        event.save(result)
        try? modelContext.save()
        insight = result
    }

    private var photo: some View {
        AnnotatedImageView(imageData: event.imageData, detections: event.detections, highlightedID: highlightedID)
            .clipShape(.rect(cornerRadius: 20))
            .animation(.smooth, value: highlightedID)
            .overlay(alignment: .bottomTrailing) {
                if event.imageData != nil {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .padding(8)
                        .glassEffect(.regular, in: .circle)
                        .padding(10)
                }
            }
            .onTapGesture { if event.imageData != nil { isViewingFullScreen = true } }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the photo full screen with pinch to zoom")
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes").font(.headline)
            TextField("Treatment applied, plant row, weather…", text: $event.notes, axis: .vertical)
                .lineLimit(3...8)
                .padding(12)
                .background(.card, in: .rect(cornerRadius: 14))
        }
    }

    // MARK: - Field validation

    private var verification: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Verify Detections").font(.headline)
                Spacer()
                let reviewed = event.boxes.filter { $0.verdict != nil }.count
                Text("\(reviewed)/\(event.boxes.count) reviewed")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            TipView(VerifyDetectionsTip())

            if sortedBoxes.isEmpty {
                Text("No leaves were detected in this scan.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }

            ForEach(sortedBoxes) { box in
                VerificationRow(
                    box: box,
                    crop: crop(for: box),
                    isHighlighted: highlightedID == box.id
                ) {
                    highlightedID = highlightedID == box.id ? nil : box.id
                }
            }
        }
        .padding()
        .background(.card, in: .rect(cornerRadius: 24))
        .sensoryFeedback(.selection, trigger: event.boxes.map(\.verdictRaw))
    }

    private func crop(for box: BoundingBox) -> UIImage? {
        guard let cgImage = decodedImage?.cgImage else { return nil }
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let rect = CGRect(x: box.x * width, y: box.y * height, width: box.width * width, height: box.height * height).integral
        return cgImage.cropping(to: rect).map { UIImage(cgImage: $0) }
    }

    // MARK: - Metadata

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailRow(title: "Severity", value: event.severity?.title ?? "No leaves", symbol: event.severity?.symbol ?? "leaf")
            Divider()
            DetailRow(title: "Infested", value: "\(event.summary.infestationRate.percentText) · \(event.aphidCount) of \(event.aphidCount + event.healthyCount) leaves", symbol: LeafClass.aphidInfested.symbol)
            Divider()
            DetailRow(title: "Field", value: event.fieldName.isEmpty ? "—" : event.fieldName, symbol: "mappin.and.ellipse")
            Divider()
            DetailRow(title: "Location check", value: verificationText, symbol: verificationSymbol)
            Divider()
            DetailRow(title: "Source", value: event.source.title, symbol: event.source.symbol)
            Divider()
            DetailRow(title: "Inference", value: "\(event.inferenceMs.fixed(1)) ms", symbol: "cpu")
            Divider()
            DetailRow(title: "Frame", value: "\(Int(event.imageWidth)) × \(Int(event.imageHeight)) px", symbol: "aspectratio")
            if let session = event.session {
                Divider()
                DetailRow(title: "Session average", value: "\(session.averageFPS.fixed(1)) FPS", symbol: "speedometer")
            }
            if let coordinate = event.coordinate {
                Divider()
                DetailRow(
                    title: "Location",
                    value: "\(coordinate.latitude.fixed(5)), \(coordinate.longitude.fixed(5))",
                    symbol: "location"
                )
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                    latitudinalMeters: 250,
                    longitudinalMeters: 250
                ))) {
                    Marker(event.fieldName, systemImage: "leaf.fill", coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))
                        .tint(event.severity?.color ?? .green)
                }
                .mapStyle(.hybrid)
                .frame(height: 160)
                .clipShape(.rect(cornerRadius: 14))
                .padding(.vertical, 8)
            }
        }
        .padding(.horizontal)
        .background(.card, in: .rect(cornerRadius: 24))
    }

    private var verificationText: String {
        switch event.geofenceVerified {
        case true?: "Inside field boundary"
        case false?: "Outside field boundary"
        case nil: event.source == .photo ? "Photo import" : "Not checked"
        }
    }

    private var verificationSymbol: String {
        switch event.geofenceVerified {
        case true?: "checkmark.seal"
        case false?: "location.slash"
        case nil: "questionmark.circle"
        }
    }
}

private struct DetailRow: View {
    let title: String
    let value: String
    let symbol: String

    var body: some View {
        LabeledContent {
            Text(value).monospacedDigit()
        } label: {
            Label(title, systemImage: symbol)
        }
        .font(.subheadline)
        .padding(.vertical, 12)
    }
}

private struct VerificationRow: View {
    @Bindable var box: BoundingBox
    let crop: UIImage?
    let isHighlighted: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    Group {
                        if let crop {
                            Image(uiImage: crop).resizable().scaledToFill()
                        } else {
                            ImagePlaceholder()
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(box.leafClass.color, lineWidth: isHighlighted ? 3 : 1.5))

                    VStack(alignment: .leading, spacing: 2) {
                        Label(box.leafClass.displayName, systemImage: box.leafClass.symbol)
                            .font(.subheadline.weight(.semibold))
                        Text("\(box.confidence.percentText) confidence")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Highlights this leaf on the image")

            verdictButton(.correct, systemImage: "checkmark", tint: .green, label: "Prediction correct")
            verdictButton(.incorrect, systemImage: "xmark", tint: .red, label: "Prediction wrong")
        }
    }

    private func verdictButton(_ verdict: Verdict, systemImage: String, tint: Color, label: String) -> some View {
        let isSelected = box.verdict == verdict
        return Button {
            withAnimation(.snappy) { box.verdict = isSelected ? nil : verdict }
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.bold))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .tint(isSelected ? tint : nil)
        .foregroundStyle(isSelected ? tint : .secondary)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
