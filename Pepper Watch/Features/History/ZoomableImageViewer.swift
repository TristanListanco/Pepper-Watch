//
//  ZoomableImageViewer.swift
//  Pepper Watch
//

import SwiftUI

/// Full-screen photo viewer: pinch to zoom, drag to pan, double-tap to toggle zoom.
struct ZoomableImageViewer: View {
    let imageData: Data?
    let detections: [Detection]

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var committedOffset: CGSize = .zero
    @State private var showsBoxes = true

    private static let scaleRange: ClosedRange<CGFloat> = 1...6

    var body: some View {
        GeometryReader { geometry in
            AnnotatedImageView(imageData: imageData, detections: showsBoxes ? detections : [])
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnification(in: geometry.size))
                .simultaneousGesture(pan(in: geometry.size))
                .onTapGesture(count: 2) {
                    withAnimation(.smooth) {
                        if scale > 1 {
                            reset()
                        } else {
                            scale = 2.5
                            committedScale = 2.5
                        }
                    }
                }
        }
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .top) {
            HStack {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                Spacer()
                Button(showsBoxes ? "Hide Boxes" : "Show Boxes", systemImage: showsBoxes ? "square.dashed" : "square.dashed.inset.filled") {
                    withAnimation { showsBoxes.toggle() }
                }
                .buttonStyle(.glass)
            }
            .padding()
        }
        .overlay(alignment: .bottom) {
            if scale > 1 {
                Text("\(Double(scale).fixed(1))×")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
            }
        }
        .statusBarHidden()
        .accessibilityAction(named: "Zoom in") { withAnimation { scale = min(scale * 1.5, Self.scaleRange.upperBound); committedScale = scale } }
        .accessibilityAction(named: "Zoom out") { withAnimation { scale = max(scale / 1.5, 1); committedScale = scale; if scale == 1 { reset() } } }
    }

    private func magnification(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(committedScale * value.magnification, Self.scaleRange.lowerBound * 0.8), Self.scaleRange.upperBound)
            }
            .onEnded { _ in
                withAnimation(.smooth) {
                    if scale <= 1 {
                        reset()
                    } else {
                        committedScale = scale
                        offset = clamped(offset, in: size)
                        committedOffset = offset
                    }
                }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1 else { return }
                offset = CGSize(
                    width: committedOffset.width + value.translation.width,
                    height: committedOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                if scale <= 1 {
                    // Swipe down to close when not zoomed.
                    if value.translation.height > 120 { dismiss() }
                    return
                }
                withAnimation(.smooth) {
                    offset = clamped(offset, in: size)
                    committedOffset = offset
                }
            }
    }

    /// Keeps the zoomed image from being dragged entirely off screen.
    private func clamped(_ proposed: CGSize, in size: CGSize) -> CGSize {
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        return CGSize(width: min(max(proposed.width, -maxX), maxX), height: min(max(proposed.height, -maxY), maxY))
    }

    private func reset() {
        scale = 1
        committedScale = 1
        offset = .zero
        committedOffset = .zero
    }
}
