//
//  PhotoAnalysisView.swift
//  Pepper Watch
//

import SwiftData
import SwiftUI

struct PhotoAnalysis: Identifiable {
    let id = UUID()
    let image: CGImage
    let detections: [Detection]
    let inferenceMs: Double

    var summary: DetectionSummary { DetectionSummary(detections) }
    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
}

/// Result sheet for running the detector on a photo from the library.
struct PhotoAnalysisView: View {
    let analysis: PhotoAnalysis

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.systemLogger) private var logger
    @AppStorage(SettingsKey.fieldName) private var fieldName = "Field A"
    @State private var isSaving = false
    @State private var isSaved = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(decorative: analysis.image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .overlay {
                            DetectionOverlay(detections: analysis.detections, imageSize: analysis.imageSize, contentMode: .fit)
                        }
                        .clipShape(.rect(cornerRadius: 20))

                    HStack(spacing: 18) {
                        ClassCountLabel(leafClass: .aphidInfested, count: analysis.summary.aphidCount)
                        ClassCountLabel(leafClass: .healthy, count: analysis.summary.healthyCount)
                        Spacer()
                        Text("\(analysis.inferenceMs.fixed(0)) ms")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)

                    if let severity = analysis.summary.severity {
                        RecommendationCard(severity: severity)
                    } else {
                        ContentUnavailableView(
                            "No Leaves Detected",
                            systemImage: "leaf",
                            description: Text("Try a closer photo of bell pepper leaves, or lower the confidence threshold in Developer settings.")
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Photo Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaved ? "Saved" : "Save", systemImage: isSaved ? "checkmark" : "square.and.arrow.down") {
                        Task { await save() }
                    }
                    .disabled(isSaving || isSaved || analysis.detections.isEmpty)
                }
            }
            .sensoryFeedback(.success, trigger: isSaved)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let encoded = await ImageEncoder.encode(analysis.image)
        let event = DetectionEvent(
            source: .photo,
            fieldName: fieldName,
            inferenceMs: analysis.inferenceMs,
            imageSize: analysis.imageSize,
            summary: analysis.summary
        )
        event.imageData = encoded.image
        event.thumbnailData = encoded.thumbnail
        modelContext.insert(event)
        event.boxes = analysis.detections.map(BoundingBox.init)
        try? modelContext.save()
        logger?.log(category: "history", "Saved photo analysis with \(analysis.detections.count) detections")
        isSaved = true
    }
}
