//
//  DetectionOverlay.swift
//  Pepper Watch
//

import SwiftUI

/// Maps normalized image coordinates into a view that shows the image with fill or fit scaling.
struct ImageTransform {
    private let displayedSize: CGSize
    private let offset: CGPoint

    init(imageSize: CGSize, viewSize: CGSize, contentMode: ContentMode) {
        guard imageSize.width > 0, imageSize.height > 0 else {
            displayedSize = viewSize
            offset = .zero
            return
        }
        let scaleX = viewSize.width / imageSize.width
        let scaleY = viewSize.height / imageSize.height
        let scale = contentMode == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY)
        displayedSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        offset = CGPoint(x: (viewSize.width - displayedSize.width) / 2, y: (viewSize.height - displayedSize.height) / 2)
    }

    func rect(for normalized: CGRect) -> CGRect {
        CGRect(
            x: offset.x + normalized.minX * displayedSize.width,
            y: offset.y + normalized.minY * displayedSize.height,
            width: normalized.width * displayedSize.width,
            height: normalized.height * displayedSize.height
        )
    }
}

/// Color-coded bounding boxes with class and confidence labels (thesis "Live Inference View").
struct DetectionOverlay: View {
    let detections: [Detection]
    let imageSize: CGSize
    var contentMode: ContentMode = .fill
    var showLabels = true
    var showConfidence = true
    var highlightedID: Detection.ID?

    var body: some View {
        let colors = Dictionary(uniqueKeysWithValues: LeafClass.allCases.map { ($0, $0.color) })
        Canvas { context, size in
            let transform = ImageTransform(imageSize: imageSize, viewSize: size, contentMode: contentMode)
            var placedChips: [CGRect] = []
            for detection in detections {
                let color = colors[detection.leafClass] ?? .white
                let isDimmed = highlightedID != nil && highlightedID != detection.id
                let rect = transform.rect(for: detection.rect)
                let shape = RoundedRectangle(cornerRadius: 6, style: .continuous).path(in: rect)

                context.opacity = isDimmed ? 0.35 : 1
                context.fill(shape, with: .color(color.opacity(0.14)))
                context.stroke(shape, with: .color(color), lineWidth: highlightedID == detection.id ? 4 : 2.5)

                guard showLabels else { continue }
                let confidence = showConfidence ? " " + detection.confidence.formatted(.percent.precision(.fractionLength(0))) : ""
                let label = Text("\(Image(systemName: detection.leafClass.symbol)) \(detection.leafClass.shortName)\(confidence)")
                let resolved = context.resolve(label.font(.caption2.weight(.semibold)).foregroundStyle(.white))
                let textSize = resolved.measure(in: size)
                let chipSize = CGSize(width: textSize.width + 10, height: textSize.height + 4)
                // Prefer above the box, then inside its top or bottom edge; skip the label rather than overlap another.
                let candidates = [
                    CGPoint(x: rect.minX, y: rect.minY - chipSize.height - 2),
                    CGPoint(x: rect.minX + 2, y: rect.minY + 2),
                    CGPoint(x: rect.minX + 2, y: rect.maxY - chipSize.height - 2),
                ]
                .map { CGRect(origin: $0, size: chipSize) }
                .filter { $0.minY >= 0 && $0.maxY <= size.height }
                guard let chip = candidates.first(where: { candidate in !placedChips.contains { $0.intersects(candidate) } }) else { continue }
                placedChips.append(chip)
                context.fill(Capsule().path(in: chip), with: .color(color))
                context.draw(resolved, at: CGPoint(x: chip.midX, y: chip.midY), anchor: .center)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let summary = DetectionSummary(detections)
        return "\(summary.aphidCount) aphid-infested and \(summary.healthyCount) healthy leaves detected"
    }
}

/// A stored image with its saved detections drawn on top.
struct AnnotatedImageView: View {
    let imageData: Data?
    let detections: [Detection]
    var highlightedID: Detection.ID?

    var body: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .overlay {
                    DetectionOverlay(detections: detections, imageSize: image.size, contentMode: .fit, highlightedID: highlightedID)
                }
        } else {
            ImagePlaceholder()
                .aspectRatio(3 / 4, contentMode: .fit)
        }
    }
}

struct ImagePlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: "leaf")
                    .font(.title)
                    .foregroundStyle(.secondary)
            }
    }
}
